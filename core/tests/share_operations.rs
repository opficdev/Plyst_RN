mod support;

use std::fs;
use std::os::unix::fs::symlink;
use std::path::Path;
use std::sync::{Arc, Mutex};

use plyst_core::operations::{
    ClipCancellationSource, ClipCodecError, ClipDownloadError, ClipImageDownloader,
    ClipOperationError, ClipShareOperations, ClipShareSaveValue,
};
use plyst_core::store::{ClipChangeValue, ClipValue};
use plyst_core::ClipContentValue;
use support::{never_cancelled, png_properties, CancelFlag, Operations, FILE_DATA};

type DownloadHook = Box<dyn FnMut(&str) -> Result<Option<String>, ClipDownloadError> + Send>;

/// 받은 주소를 기록하고 시험 동작으로 내려받기를 대신하는 대역
struct RecordedDownloads {
    urls: Mutex<Vec<String>>,
    hook: Mutex<DownloadHook>,
}

impl RecordedDownloads {
    fn new(
        hook: impl FnMut(&str) -> Result<Option<String>, ClipDownloadError> + Send + 'static,
    ) -> Arc<Self> {
        Arc::new(Self {
            urls: Mutex::new(Vec::new()),
            hook: Mutex::new(Box::new(hook)),
        })
    }

    /// 원본 바이트를 쓰고 지정한 응답 형식을 돌려줌
    fn writing(content_type: Option<&str>) -> Arc<Self> {
        let content_type = content_type.map(str::to_string);
        Self::new(move |path| {
            fs::write(path, FILE_DATA).unwrap();
            Ok(content_type.clone())
        })
    }

    fn urls(&self) -> Vec<String> {
        self.urls.lock().unwrap().clone()
    }
}

impl ClipImageDownloader for RecordedDownloads {
    fn download(
        &self,
        url: String,
        path: String,
        _: Arc<dyn ClipCancellationSource>,
    ) -> Result<Option<String>, ClipDownloadError> {
        self.urls.lock().unwrap().push(url);
        (self.hook.lock().unwrap())(&path)
    }
}

const IMAGE_URL: &str = "https://example.com/사진.png?size=1";
const IMAGE_URL_NORMALIZED: &str = "https://example.com/%EC%82%AC%EC%A7%84.png?size=1";

struct Fixture {
    operations: Operations,
    share: Arc<ClipShareOperations>,
}

impl Fixture {
    fn new() -> Self {
        let operations = Operations::new();
        let share = ClipShareOperations::new(operations.images.clone());
        Self { operations, share }
    }

    fn save(
        &self,
        text: &str,
        downloads: &Arc<RecordedDownloads>,
    ) -> Result<ClipShareSaveValue, ClipOperationError> {
        self.share.save_text(
            text.to_string(),
            Some("  제목 \n".to_string()),
            true,
            downloads.clone(),
            never_cancelled(),
        )
    }

    fn saved(&self, text: &str, downloads: &Arc<RecordedDownloads>) -> ClipValue {
        let ClipShareSaveValue::Saved { clip } = self.save(text, downloads).unwrap() else {
            panic!("저장 결과 누락");
        };
        clip
    }
}

fn assert_text(clip: &ClipValue, text: &str) {
    assert_eq!(
        clip.content,
        ClipContentValue::Text {
            text: text.to_string()
        }
    );
    assert_eq!(clip.name.as_deref(), Some("제목"));
    assert_eq!(clip.memo, None);
}

#[test]
fn blank_text_is_empty_and_writes_nothing() {
    let fixture = Fixture::new();
    let downloads = RecordedDownloads::writing(Some("image/png"));
    assert_eq!(
        fixture.save(" \n\u{3000}", &downloads),
        Ok(ClipShareSaveValue::Empty)
    );
    assert!(downloads.urls().is_empty());
    assert!(fixture.operations.changes.taken().is_empty());
}

#[test]
fn page_link_is_saved_as_text_with_trimmed_title_without_download() {
    let fixture = Fixture::new();
    let downloads = RecordedDownloads::writing(Some("image/png"));
    let clip = fixture.saved("https://example.com/page", &downloads);
    assert_text(&clip, "https://example.com/page");
    assert!(downloads.urls().is_empty());
    assert_eq!(
        fixture.operations.changes.taken(),
        vec![ClipChangeValue::Inserted { clip }]
    );
}

#[test]
fn image_link_is_not_downloaded_when_the_input_forbids_it() {
    let fixture = Fixture::new();
    let downloads = RecordedDownloads::writing(Some("image/png"));
    let saved = fixture
        .share
        .save_text(
            IMAGE_URL.to_string(),
            None,
            false,
            downloads.clone(),
            never_cancelled(),
        )
        .unwrap();
    let ClipShareSaveValue::Saved { clip } = saved else {
        panic!("저장 결과 누락");
    };
    assert!(matches!(clip.content, ClipContentValue::Text { .. }));
    assert!(downloads.urls().is_empty());
}

#[test]
fn downloaded_image_keeps_the_normalized_link_as_memo_without_name() {
    let fixture = Fixture::new();
    let downloads = RecordedDownloads::writing(Some("IMAGE/PNG; charset=binary"));
    let clip = fixture.saved(IMAGE_URL, &downloads);
    assert_eq!(downloads.urls(), vec![IMAGE_URL_NORMALIZED.to_string()]);
    assert_eq!(clip.memo.as_deref(), Some(IMAGE_URL_NORMALIZED));
    assert_eq!(clip.name, None);
    let ClipContentValue::Image {
        file_id,
        content_type,
        byte_count,
        ..
    } = &clip.content
    else {
        panic!("이미지 클립이 아님");
    };
    assert_eq!(content_type, &png_properties().content_type);
    assert_eq!(*byte_count, FILE_DATA.len() as i64);
    let folder = fixture.operations.folder(file_id);
    assert_eq!(fs::read(folder.join("original")).unwrap(), FILE_DATA);
    assert!(!folder.join("pending").exists());
    assert!(!folder.join("download").exists());
    assert_eq!(
        fixture.operations.changes.taken(),
        vec![ClipChangeValue::Inserted { clip }]
    );
}

#[test]
fn unknown_response_type_is_decided_by_the_codec() {
    let fixture = Fixture::new();
    let downloads = RecordedDownloads::writing(None);
    let clip = fixture.saved(IMAGE_URL, &downloads);
    assert!(matches!(clip.content, ClipContentValue::Image { .. }));

    *fixture.operations.codec.properties.lock().unwrap() = Err(ClipCodecError::Corrupted);
    let downloads = RecordedDownloads::writing(Some("text/plain"));
    let clip = fixture.saved(IMAGE_URL, &downloads);
    assert_text(&clip, IMAGE_URL);
    assert_eq!(fixture.operations.folders().len(), 1);
}

#[test]
fn failed_or_non_image_downloads_fall_back_to_the_same_text() {
    let fixture = Fixture::new();
    for downloads in [
        RecordedDownloads::new(|_| Err(ClipDownloadError::Failed)),
        RecordedDownloads::new(|_| Err(ClipDownloadError::Unexpected)),
        RecordedDownloads::writing(Some("image/x-icon")),
        RecordedDownloads::writing(Some("application/octet-stream")),
    ] {
        let clip = fixture.saved(IMAGE_URL, &downloads);
        assert_text(&clip, IMAGE_URL);
        assert_eq!(downloads.urls().len(), 1);
    }
    assert!(fixture.operations.folders().is_empty());
}

#[test]
fn cancellation_during_download_saves_nothing_and_removes_the_folder() {
    let fixture = Fixture::new();
    let flag = Arc::new(CancelFlag::default());
    let cancel = flag.clone();
    let downloads = RecordedDownloads::new(move |path| {
        fs::write(path, FILE_DATA).unwrap();
        cancel.cancel();
        Err(ClipDownloadError::Failed)
    });
    let saved = fixture.share.save_text(
        IMAGE_URL.to_string(),
        None,
        true,
        downloads.clone(),
        flag.clone(),
    );
    assert_eq!(saved, Err(ClipOperationError::Cancelled));
    assert!(fixture.operations.folders().is_empty());
    assert!(fixture.operations.changes.taken().is_empty());
}

#[test]
fn cancellation_after_a_finished_download_removes_the_original() {
    let fixture = Fixture::new();
    let flag = Arc::new(CancelFlag::default());
    let cancel = flag.clone();
    let downloads = RecordedDownloads::new(move |path| {
        fs::write(path, FILE_DATA).unwrap();
        cancel.cancel();
        Ok(Some("image/png".to_string()))
    });
    let saved = fixture.share.save_text(
        IMAGE_URL.to_string(),
        None,
        true,
        downloads.clone(),
        flag.clone(),
    );
    assert_eq!(saved, Err(ClipOperationError::Cancelled));
    assert!(fixture.operations.folders().is_empty());
    assert!(fixture.operations.changes.taken().is_empty());
}

#[test]
fn recovery_during_a_download_keeps_the_reserved_folder() {
    let fixture = Fixture::new();
    let images = fixture.operations.images.clone();
    let downloads = RecordedDownloads::new(move |path| {
        assert_eq!(
            images.recover_pending_cleanup(never_cancelled()),
            Ok(Vec::new())
        );
        fs::write(path, FILE_DATA).unwrap();
        Ok(Some("image/png".to_string()))
    });
    let clip = fixture.saved(IMAGE_URL, &downloads);
    assert!(matches!(clip.content, ClipContentValue::Image { .. }));
}

#[test]
fn a_folder_left_by_a_stopped_download_is_removed_by_the_next_recovery() {
    let fixture = Fixture::new();
    let downloads = RecordedDownloads::new(|path| {
        fs::write(path, FILE_DATA).unwrap();
        let folder = Path::new(path).parent().unwrap();
        // 내려받기 도중 프로세스가 멈춘 상태를 남김
        let copy = folder.with_file_name("00000000-0000-4000-8000-0000000000AA");
        fs::create_dir(&copy).unwrap();
        fs::write(copy.join("pending"), b"").unwrap();
        fs::write(copy.join("download"), FILE_DATA).unwrap();
        Err(ClipDownloadError::Failed)
    });
    fixture.saved(IMAGE_URL, &downloads);
    assert_eq!(
        fixture.operations.folders(),
        vec!["00000000-0000-4000-8000-0000000000AA".to_string()]
    );
    let reopened = fixture.operations.reopened();
    assert_eq!(
        reopened.recover_pending_cleanup(never_cancelled()),
        Ok(Vec::new())
    );
    assert!(fixture.operations.folders().is_empty());
}

#[test]
fn a_link_or_oversized_file_is_refused_before_it_becomes_the_original() {
    let fixture = Fixture::new();
    let target = fixture.operations.directory.0.join("outside");
    fs::write(&target, FILE_DATA).unwrap();
    let linked = target.clone();
    let downloads = RecordedDownloads::new(move |path| {
        symlink(&linked, path).unwrap();
        Ok(Some("image/png".to_string()))
    });
    assert!(matches!(
        fixture.save(IMAGE_URL, &downloads),
        Err(ClipOperationError::Files { .. })
    ));
    let downloads = RecordedDownloads::new(|path| {
        let file = fs::File::create(path).unwrap();
        file.set_len(20 * 1024 * 1024 + 1).unwrap();
        Ok(Some("image/png".to_string()))
    });
    assert!(matches!(
        fixture.save(IMAGE_URL, &downloads),
        Err(ClipOperationError::Files { .. })
    ));
    assert!(fixture.operations.folders().is_empty());
    assert_eq!(fs::read(&target).unwrap(), FILE_DATA);
    assert!(fixture.operations.changes.taken().is_empty());
}
