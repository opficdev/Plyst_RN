mod support;

use std::fs;
use std::sync::{Arc, Mutex};

use plyst_core::operations::{
    ClipCancellationSource, ClipOperationError, ClipboardCopyValue, ClipboardOperations,
    ClipboardSaveValue, ClipboardUsageFailureValue, ClipboardWriteError, ClipboardWriteOutcome,
    ClipboardWriteValue, ClipboardWriting,
};
use plyst_core::store::{ClipChangeValue, ClipStoreError, ClipUpdateValue, ClipValue};
use plyst_core::ClipContentValue;
use support::{
    execute, never_cancelled, png_properties, CancelFlag, CancelledAfter, Operations, FILE_DATA,
};

type WriteHook = Box<dyn FnMut() + Send>;

/// 쓰기 내용을 기록하고 쓰기 시점에 시험 동작을 실행하는 대역
struct RecordedWrites {
    contents: Mutex<Vec<ClipboardWriteValue>>,
    outcome: Mutex<Result<ClipboardWriteOutcome, ClipboardWriteError>>,
    hook: Mutex<Option<WriteHook>>,
}

impl RecordedWrites {
    fn observed() -> Arc<Self> {
        Arc::new(Self {
            contents: Mutex::new(Vec::new()),
            outcome: Mutex::new(Ok(ClipboardWriteOutcome::Observed)),
            hook: Mutex::new(None),
        })
    }

    fn on_write(&self, hook: impl FnMut() + Send + 'static) {
        *self.hook.lock().unwrap() = Some(Box::new(hook));
    }
}

impl ClipboardWriting for RecordedWrites {
    fn write(
        &self,
        content: ClipboardWriteValue,
    ) -> Result<ClipboardWriteOutcome, ClipboardWriteError> {
        if let Some(hook) = self.hook.lock().unwrap().as_mut() {
            hook();
        }
        self.contents.lock().unwrap().push(content);
        self.outcome.lock().unwrap().clone()
    }
}

struct Fixture {
    operations: Operations,
    writes: Arc<RecordedWrites>,
    clipboard: Arc<ClipboardOperations>,
}

impl Fixture {
    fn new() -> Self {
        let operations = Operations::new();
        let writes = RecordedWrites::observed();
        let clipboard = ClipboardOperations::new(operations.images.clone(), writes.clone());
        Self {
            operations,
            writes,
            clipboard,
        }
    }

    fn text_clip(&self) -> ClipValue {
        let clip = ClipValue {
            id: "00000000-0000-4000-8000-000000000001".to_string(),
            content: ClipContentValue::Text {
                text: " \n한글 'text'\0🙂\t ".to_string(),
            },
            name: Some("이름".to_string()),
            pinned_at: Some(1.0),
            memo: Some("메모".to_string()),
            created_at: 100.0,
            last_used_at: Some(50.0),
        };
        self.operations.store.insert(clip.clone()).unwrap();
        self.operations.changes.taken();
        clip
    }

    fn copy(&self, clip: &ClipValue) -> Result<ClipboardCopyValue, ClipOperationError> {
        self.clipboard.copy(clip.id.clone(), never_cancelled())
    }

    fn cancelled_copy(
        &self,
        clip: &ClipValue,
        cancellation: Arc<dyn ClipCancellationSource>,
    ) -> Result<ClipboardCopyValue, ClipOperationError> {
        self.clipboard.copy(clip.id.clone(), cancellation)
    }
}

#[test]
fn text_copy_preserves_details_and_commits_usage_and_event() {
    let fixture = Fixture::new();
    let clip = fixture.text_clip();
    let ClipboardCopyValue::Copied { clip: updated } = fixture.copy(&clip).unwrap() else {
        panic!("복사 성공 결과 누락");
    };
    assert_eq!(
        updated,
        ClipValue {
            last_used_at: updated.last_used_at,
            ..clip.clone()
        }
    );
    assert_ne!(updated.last_used_at, clip.last_used_at);
    assert_eq!(
        fixture
            .operations
            .store
            .fetch(clip.id.clone())
            .unwrap()
            .as_ref(),
        Some(&updated)
    );
    assert_eq!(
        fixture.operations.changes.taken(),
        vec![ClipChangeValue::Updated { clip: updated }]
    );
    let ClipContentValue::Text { text } = clip.content else {
        panic!("텍스트 클립이 아님");
    };
    assert_eq!(
        *fixture.writes.contents.lock().unwrap(),
        vec![ClipboardWriteValue::Text { text }]
    );
}

#[test]
fn image_copy_writes_the_checked_original_path() {
    let fixture = Fixture::new();
    let saved = fixture
        .clipboard
        .save_image(FILE_DATA, png_properties(), never_cancelled())
        .unwrap();
    let ClipboardSaveValue::Saved { clip } = saved else {
        panic!("저장 성공 결과 누락");
    };
    assert!(matches!(
        fixture.copy(&clip).unwrap(),
        ClipboardCopyValue::Copied { .. }
    ));
    let contents = fixture.writes.contents.lock().unwrap();
    let ClipboardWriteValue::Image { path, content_type } = &contents[0] else {
        panic!("이미지 쓰기 누락");
    };
    assert_eq!(content_type, "public.png");
    assert_eq!(fs::read(path).unwrap(), FILE_DATA);
}

#[test]
fn missing_clip_is_not_found_and_writes_nothing() {
    let fixture = Fixture::new();
    let clip = fixture.text_clip();
    fixture.operations.store.delete(clip.id.clone()).unwrap();
    assert_eq!(
        fixture.copy(&clip).unwrap_err(),
        ClipOperationError::Storage {
            error: ClipStoreError::NotFound { id: clip.id }
        }
    );
    assert!(fixture.writes.contents.lock().unwrap().is_empty());
}

#[test]
fn cancelled_before_write_leaves_the_clipboard() {
    let fixture = Fixture::new();
    let clip = fixture.text_clip();
    for reads in [0, 1] {
        let result = fixture.cancelled_copy(&clip, CancelledAfter::reads(reads));
        assert_eq!(result.unwrap_err(), ClipOperationError::Cancelled);
    }
    assert!(fixture.writes.contents.lock().unwrap().is_empty());
}

#[test]
fn unobserved_write_skips_usage() {
    let fixture = Fixture::new();
    let clip = fixture.text_clip();
    *fixture.writes.outcome.lock().unwrap() = Ok(ClipboardWriteOutcome::NotObserved);
    assert_eq!(
        fixture.copy(&clip).unwrap(),
        ClipboardCopyValue::WriteNotObserved {
            id: clip.id.clone()
        }
    );
    assert_eq!(
        fixture.operations.store.fetch(clip.id.clone()).unwrap(),
        Some(clip)
    );
}

#[test]
fn write_failures_before_writing_are_propagated() {
    let fixture = Fixture::new();
    let clip = fixture.text_clip();
    for (error, expected) in [
        (
            ClipboardWriteError::Cancelled,
            ClipOperationError::Cancelled,
        ),
        (
            ClipboardWriteError::Unexpected,
            ClipOperationError::ClipboardWriteFailed,
        ),
    ] {
        *fixture.writes.outcome.lock().unwrap() = Err(error);
        assert_eq!(fixture.copy(&clip).unwrap_err(), expected);
    }
}

#[test]
fn cancelled_after_observed_write_reports_copy_without_usage() {
    let fixture = Fixture::new();
    let clip = fixture.text_clip();
    let flag = Arc::new(CancelFlag::default());
    let cancel = flag.clone();
    fixture.writes.on_write(move || cancel.cancel());
    let ClipboardCopyValue::CopiedWithoutLastUsedAt {
        clip: copied,
        failure,
        ..
    } = fixture.cancelled_copy(&clip, flag).unwrap()
    else {
        panic!("부분 성공 결과 누락");
    };
    assert_eq!(copied, clip);
    assert_eq!(failure, ClipboardUsageFailureValue::Cancelled);
}

#[test]
fn failed_usage_update_reports_the_storage_cause() {
    let fixture = Fixture::new();
    let clip = fixture.text_clip();
    let database = fixture.operations.directory.database();
    fixture.writes.on_write(move || {
        execute(
            &database,
            "CREATE TRIGGER reject BEFORE UPDATE ON clips BEGIN SELECT RAISE(ABORT, 'x'); END;",
        );
    });
    let ClipboardCopyValue::CopiedWithoutLastUsedAt { failure, .. } = fixture.copy(&clip).unwrap()
    else {
        panic!("부분 성공 결과 누락");
    };
    assert!(matches!(
        failure,
        ClipboardUsageFailureValue::Storage {
            error: ClipStoreError::WriteFailed { .. }
        }
    ));
}

#[test]
fn reinserted_clip_does_not_receive_old_copy_usage_or_event() {
    let fixture = Fixture::new();
    let clip = fixture.text_clip();
    let replacement = ClipValue {
        created_at: 200.0,
        last_used_at: None,
        ..clip.clone()
    };
    let store = fixture.operations.store.clone();
    let (id, inserted) = (clip.id.clone(), replacement.clone());
    fixture.writes.on_write(move || {
        store.delete(id.clone()).unwrap();
        store.insert(inserted.clone()).unwrap();
    });
    let ClipboardCopyValue::CopiedWithoutLastUsedAt {
        clip: copied,
        failure,
        ..
    } = fixture.copy(&clip).unwrap()
    else {
        panic!("교체된 클립의 부분 성공 결과 누락");
    };
    assert_eq!(copied, clip);
    assert_eq!(failure, ClipboardUsageFailureValue::Replaced);
    assert_eq!(
        fixture
            .operations
            .store
            .fetch(clip.id.clone())
            .unwrap()
            .as_ref(),
        Some(&replacement)
    );
    assert_eq!(
        fixture.operations.changes.taken(),
        vec![
            ClipChangeValue::Deleted { id: clip.id },
            ClipChangeValue::Inserted { clip: replacement }
        ]
    );
}

#[test]
fn copy_updates_usage_without_overwriting_details_edited_after_write() {
    let fixture = Fixture::new();
    let clip = fixture.text_clip();
    let store = fixture.operations.store.clone();
    let id = clip.id.clone();
    fixture.writes.on_write(move || {
        let details = ClipUpdateValue::Details {
            name: Some("새 이름".to_string()),
            memo: Some("새 메모".to_string()),
            is_pinned: true,
            requested_at: 300.0,
        };
        store.update(id.clone(), details).unwrap();
    });
    let ClipboardCopyValue::Copied { clip: copied } = fixture.copy(&clip).unwrap() else {
        panic!("상세 편집과 병행한 복사 성공 결과 누락");
    };
    assert_eq!(copied.name.as_deref(), Some("새 이름"));
    assert_eq!(copied.memo.as_deref(), Some("새 메모"));
    assert!(copied.last_used_at.is_some());
}

#[test]
fn saved_text_uses_core_identifier_and_blank_text_is_empty() {
    let fixture = Fixture::new();
    let empty = fixture
        .clipboard
        .save_text("  \n".to_string(), never_cancelled());
    assert_eq!(empty.unwrap(), ClipboardSaveValue::Empty);
    let saved = fixture
        .clipboard
        .save_text("내용".to_string(), never_cancelled());
    let ClipboardSaveValue::Saved { clip } = saved.unwrap() else {
        panic!("저장 성공 결과 누락");
    };
    assert_eq!(clip.id.to_uppercase(), clip.id);
    assert_eq!(
        fixture.operations.store.fetch(clip.id.clone()).unwrap(),
        Some(clip)
    );
}

#[test]
fn cancelled_text_save_stores_nothing() {
    let fixture = Fixture::new();
    let saved = fixture
        .clipboard
        .save_text("내용".to_string(), CancelledAfter::reads(0));
    assert_eq!(saved.unwrap_err(), ClipOperationError::Cancelled);
    assert!(fixture.operations.changes.taken().is_empty());
}
