#![allow(dead_code)]

use std::fs;
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering};
use std::sync::{Arc, Mutex};

use plyst_core::operations::{
    ClipCancellationSource, ClipCodecError, ClipImageCoding, ClipImageOperations,
    ClipImagePropertiesValue, ClipImageValue,
};
use plyst_core::store::{
    ClipChangeListener, ClipChangeValue, ClipContentValue, ClipStore, ClipStoreError, ClipValue,
};
use plyst_core::ClipIdentity;
use rusqlite::Connection;

static NEXT: AtomicUsize = AtomicUsize::new(0);

pub const CORRUPTED: ClipStoreError = ClipStoreError::CorruptedData {
    code: 0,
    extended_code: 0,
};

/// 시험마다 지워지는 임시 디렉터리
pub struct Directory(pub PathBuf);

impl Directory {
    pub fn new() -> Self {
        let path = std::env::temp_dir().join(format!(
            "plyst-core-{}-{}",
            std::process::id(),
            NEXT.fetch_add(1, Ordering::Relaxed)
        ));
        fs::create_dir_all(&path).unwrap();
        Self(path)
    }

    pub fn images(&self) -> String {
        self.0.join("images").to_str().unwrap().to_string()
    }

    pub fn database(&self) -> String {
        self.0.join("clips.sqlite").to_str().unwrap().to_string()
    }

    pub fn copy_fixture(&self, name: &str) -> String {
        let source = Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("tests/fixtures")
            .join(name);
        for entry in fs::read_dir(source).unwrap() {
            let entry = entry.unwrap();
            fs::copy(entry.path(), self.0.join(entry.file_name())).unwrap();
        }
        self.database()
    }
}

impl Drop for Directory {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.0);
    }
}

/// 변경 알림을 쓰지 않는 시험의 리스너
pub struct IgnoredChanges;

impl ClipChangeListener for IgnoredChanges {
    fn changed(&self, _: ClipChangeValue) {}
}

pub fn ignored_changes() -> Arc<dyn ClipChangeListener> {
    Arc::new(IgnoredChanges)
}

pub fn open(path: &str) -> Arc<ClipStore> {
    ClipStore::open(path.to_string(), ignored_changes()).unwrap()
}

/// 코어 밖의 별도 연결로 저장값을 바꾸어 실패를 재현
pub fn execute(path: &str, sql: &str) {
    Connection::open(path).unwrap().execute_batch(sql).unwrap();
}

pub fn text(id: &str, value: &str) -> ClipValue {
    ClipValue {
        id: id.to_string(),
        content: ClipContentValue::Text {
            text: value.to_string(),
        },
        name: None,
        pinned_at: None,
        memo: None,
        created_at: 793109282.0612345,
        last_used_at: None,
    }
}

pub fn image(id: &str, file_id: &str) -> ClipValue {
    ClipValue {
        content: ClipContentValue::Image {
            file_id: file_id.to_string(),
            content_type: "public.png".to_string(),
            pixel_width: 640,
            pixel_height: 480,
            byte_count: 4096,
        },
        ..text(id, "")
    }
}

pub fn identity(clip: &ClipValue) -> ClipIdentity {
    ClipIdentity {
        id: clip.id.clone(),
        content: clip.content.clone(),
        created_at: clip.created_at,
    }
}

pub const FILE_DATA: &[u8] = b"original bytes";

type Hook = Box<dyn FnMut(&ClipChangeValue) + Send>;

/// 받은 변경을 기록하고 첫 변경에서 시험 동작을 실행
#[derive(Default)]
pub struct RecordedChanges {
    pub changes: Mutex<Vec<ClipChangeValue>>,
    hook: Mutex<Option<Hook>>,
}

impl RecordedChanges {
    pub fn on_next_change(&self, hook: impl FnMut(&ClipChangeValue) + Send + 'static) {
        *self.hook.lock().unwrap() = Some(Box::new(hook));
    }

    pub fn taken(&self) -> Vec<ClipChangeValue> {
        std::mem::take(&mut self.changes.lock().unwrap())
    }
}

impl ClipChangeListener for RecordedChanges {
    fn changed(&self, change: ClipChangeValue) {
        if let Some(mut hook) = self.hook.lock().unwrap().take() {
            hook(&change);
        }
        self.changes.lock().unwrap().push(change);
    }
}

/// 지정한 횟수만큼 읽힌 뒤 취소 상태가 되는 대역
pub struct CancelledAfter {
    remaining: AtomicUsize,
}

impl CancelledAfter {
    pub fn reads(count: usize) -> Arc<dyn ClipCancellationSource> {
        Arc::new(Self {
            remaining: AtomicUsize::new(count),
        })
    }
}

impl ClipCancellationSource for CancelledAfter {
    fn is_cancelled(&self) -> bool {
        self.remaining
            .try_update(Ordering::Relaxed, Ordering::Relaxed, |count| {
                count.checked_sub(1)
            })
            .is_err()
    }
}

/// 시험 동작이 켜는 취소 상태
#[derive(Default)]
pub struct CancelFlag(pub AtomicBool);

impl CancelFlag {
    pub fn cancel(&self) {
        self.0.store(true, Ordering::Relaxed);
    }
}

impl ClipCancellationSource for CancelFlag {
    fn is_cancelled(&self) -> bool {
        self.0.load(Ordering::Relaxed)
    }
}

pub fn never_cancelled() -> Arc<dyn ClipCancellationSource> {
    Arc::new(CancelFlag::default())
}

pub fn png_properties() -> ClipImagePropertiesValue {
    ClipImagePropertiesValue {
        content_type: "public.png".to_string(),
        pixel_width: 2,
        pixel_height: 3,
    }
}

/// 저장된 메타데이터와 맞는 값을 돌려주는 코덱
pub struct FixedCodec {
    pub properties: Mutex<Result<ClipImagePropertiesValue, ClipCodecError>>,
}

impl ClipImageCoding for FixedCodec {
    fn properties(&self, _: String) -> Result<ClipImagePropertiesValue, ClipCodecError> {
        self.properties.lock().unwrap().clone()
    }

    fn thumbnail(&self, _: String, _: ClipImageValue, _: i64) -> Result<Vec<u8>, ClipCodecError> {
        Ok(b"derived".to_vec())
    }
}

/// 이미지 작업 시험의 저장소, 파일 루트, 리스너
pub struct Operations {
    pub directory: Directory,
    pub store: Arc<ClipStore>,
    pub changes: Arc<RecordedChanges>,
    pub codec: Arc<FixedCodec>,
    pub images: Arc<ClipImageOperations>,
}

impl Operations {
    pub fn new() -> Self {
        let directory = Directory::new();
        let changes = Arc::new(RecordedChanges::default());
        let store = ClipStore::open(directory.database(), changes.clone()).unwrap();
        let codec = Arc::new(FixedCodec {
            properties: Mutex::new(Ok(png_properties())),
        });
        let images =
            ClipImageOperations::open(store.clone(), directory.images(), codec.clone()).unwrap();
        Self {
            directory,
            store,
            changes,
            codec,
            images,
        }
    }

    /// 같은 위치를 다시 열어 프로세스 재시작을 재현
    pub fn reopened(&self) -> Arc<ClipImageOperations> {
        let store = ClipStore::open(self.directory.database(), ignored_changes()).unwrap();
        ClipImageOperations::open(store, self.directory.images(), self.codec.clone()).unwrap()
    }

    pub fn folder(&self, file_id: &str) -> PathBuf {
        self.directory.0.join("images").join(file_id)
    }

    pub fn folders(&self) -> Vec<String> {
        let mut names: Vec<String> = fs::read_dir(self.directory.0.join("images"))
            .unwrap()
            .map(|entry| entry.unwrap().file_name().into_string().unwrap())
            .collect();
        names.sort();
        names
    }
}

pub fn make_read_only(path: &Path) {
    fs::set_permissions(path, fs::Permissions::from_mode(0o500)).unwrap();
}

pub fn make_writable(path: &Path) {
    fs::set_permissions(path, fs::Permissions::from_mode(0o700)).unwrap();
}

pub fn file_id(clip: &ClipValue) -> String {
    match &clip.content {
        ClipContentValue::Image { file_id, .. } => file_id.clone(),
        ClipContentValue::Text { .. } => panic!("이미지 클립이 아님"),
    }
}

pub fn image_value(clip: &ClipValue) -> ClipImageValue {
    match &clip.content {
        ClipContentValue::Image {
            file_id,
            content_type,
            pixel_width,
            pixel_height,
            byte_count,
        } => ClipImageValue {
            file_id: file_id.clone(),
            content_type: content_type.clone(),
            pixel_width: *pixel_width,
            pixel_height: *pixel_height,
            byte_count: *byte_count,
        },
        ClipContentValue::Text { .. } => panic!("이미지 클립이 아님"),
    }
}
