use std::panic::{catch_unwind, AssertUnwindSafe};
use std::sync::Arc;

use super::error::ClipOperationError;
use super::image::{check, new_draft, ClipCleanupValue, ClipImageOperations};
use super::platform::{
    ClipCancellationSource, ClipImagePropertiesValue, ClipImageValue, ClipboardWriteOutcome,
    ClipboardWriteValue, ClipboardWriter,
};
use super::{now, NO_RANDOM};
use crate::store::{ClipStoreError, ClipUpdateResult, ClipUpdateValue, ClipValue};
use crate::uuid_form::new_uuid;
use crate::{content, ClipContentValue, ClipIdentity};

#[derive(Clone, Debug, PartialEq, uniffi::Enum)]
pub enum ClipboardSaveValue {
    Saved { clip: ClipValue },
    SavedWithPendingCleanup { clip: ClipValue, file_id: String },
    Empty,
}

#[derive(Clone, Debug, PartialEq, Eq, uniffi::Enum)]
pub enum ClipboardUsageFailureValue {
    Cancelled,
    Storage { error: ClipStoreError },
    Replaced,
    Unknown,
}

#[derive(Clone, Debug, PartialEq, uniffi::Enum)]
pub enum ClipboardCopyValue {
    Copied {
        clip: ClipValue,
    },
    WriteNotObserved {
        id: String,
    },
    CopiedWithoutLastUsedAt {
        clip: ClipValue,
        copied_at: f64,
        failure: ClipboardUsageFailureValue,
    },
}

/// 저장과 복사의 순서
/// 저장소는 `images`의 것을 써서 서로 다른 저장소가 섞이지 않음
#[derive(uniffi::Object)]
pub struct ClipboardOperations {
    images: Arc<ClipImageOperations>,
}

#[uniffi::export]
impl ClipboardOperations {
    #[uniffi::constructor]
    pub fn new(images: Arc<ClipImageOperations>) -> Arc<Self> {
        Arc::new(Self { images })
    }

    /// 호스트가 읽은 텍스트를 저장
    /// 저장 확정 뒤에는 취소를 확인하지 않음
    pub fn save_text(
        &self,
        text: String,
        cancellation: Arc<dyn ClipCancellationSource>,
    ) -> Result<ClipboardSaveValue, ClipOperationError> {
        if !content::is_text_valid(&text) {
            return Ok(ClipboardSaveValue::Empty);
        }
        check(&cancellation)?;
        let clip = ClipValue {
            id: new_uuid().ok_or(NO_RANDOM)?,
            content: ClipContentValue::Text { text },
            name: None,
            pinned_at: None,
            memo: None,
            created_at: now(),
            last_used_at: None,
        };
        self.images.store().insert(clip.clone())?;
        Ok(ClipboardSaveValue::Saved { clip })
    }

    /// 호스트가 읽고 검증한 이미지를 저장
    pub fn save_image(
        &self,
        data: &[u8],
        properties: ClipImagePropertiesValue,
        cancellation: Arc<dyn ClipCancellationSource>,
    ) -> Result<ClipboardSaveValue, ClipOperationError> {
        check(&cancellation)?;
        let saved = self
            .images
            .save_image(data, properties, new_draft()?, cancellation)?;
        Ok(match saved.cleanup {
            ClipCleanupValue::Completed => ClipboardSaveValue::Saved { clip: saved.clip },
            ClipCleanupValue::Pending { file_id } => ClipboardSaveValue::SavedWithPendingCleanup {
                clip: saved.clip,
                file_id,
            },
        })
    }

    /// 쓰기 전 오류는 전파
    /// 쓰기가 확인된 뒤의 사용 시각 저장 실패는 부분 성공으로 돌려줌
    pub fn copy(
        &self,
        id: String,
        writer: Arc<dyn ClipboardWriter>,
        cancellation: Arc<dyn ClipCancellationSource>,
    ) -> Result<ClipboardCopyValue, ClipOperationError> {
        check(&cancellation)?;
        let store = self.images.store();
        let Some(clip) = store.fetch(id.clone())? else {
            return Err(ClipStoreError::NotFound { id }.into());
        };
        let outcome = match &clip.content {
            ClipContentValue::Text { text } => {
                check(&cancellation)?;
                write(&writer, ClipboardWriteValue::Text { text: text.clone() })?
            }
            // 경로를 넘기므로 쓰기가 끝날 때까지 삭제와 섞이지 않게 잠금을 유지
            // 같은 클립 식별자가 재사용돼도 최초 조회한 메타데이터와 다른 원본을 섞지 않음
            ClipContentValue::Image {
                file_id,
                content_type,
                pixel_width,
                pixel_height,
                byte_count,
            } => {
                let _order = self.images.lock();
                check(&cancellation)?;
                let path = self.images.checked_original(&ClipImageValue {
                    file_id: file_id.clone(),
                    content_type: content_type.clone(),
                    pixel_width: *pixel_width,
                    pixel_height: *pixel_height,
                    byte_count: *byte_count,
                })?;
                check(&cancellation)?;
                write(
                    &writer,
                    ClipboardWriteValue::Image {
                        path,
                        content_type: content_type.clone(),
                    },
                )?
            }
        };
        if outcome != ClipboardWriteOutcome::Observed {
            return Ok(ClipboardCopyValue::WriteNotObserved { id });
        }
        let copied_at = now();
        let partial = |clip, failure| ClipboardCopyValue::CopiedWithoutLastUsedAt {
            clip,
            copied_at,
            failure,
        };
        if cancellation.is_cancelled() {
            return Ok(partial(clip, ClipboardUsageFailureValue::Cancelled));
        }
        // 쓰기가 끝난 복사를 패닉으로 숨기지 않음
        let updated = catch_unwind(AssertUnwindSafe(|| {
            self.record_usage(&clip, id.clone(), copied_at)
        }));
        Ok(match updated {
            Err(_) => partial(clip, ClipboardUsageFailureValue::Unknown),
            Ok(Err(error)) => partial(clip, ClipboardUsageFailureValue::Storage { error }),
            Ok(Ok(result)) if is_same_clip(&result.clip, &clip) => {
                ClipboardCopyValue::Copied { clip: result.clip }
            }
            Ok(Ok(_)) => partial(clip, ClipboardUsageFailureValue::Replaced),
        })
    }
}

impl ClipboardOperations {
    fn record_usage(
        &self,
        clip: &ClipValue,
        id: String,
        date: f64,
    ) -> Result<ClipUpdateResult, ClipStoreError> {
        let matching = ClipIdentity {
            id: clip.id.clone(),
            content: clip.content.clone(),
            created_at: clip.created_at,
        };
        self.images.store().update(
            id,
            ClipUpdateValue::LastUsedAt {
                date,
                matching: Some(matching),
            },
        )
    }
}

fn write(
    writer: &Arc<dyn ClipboardWriter>,
    content: ClipboardWriteValue,
) -> Result<ClipboardWriteOutcome, ClipOperationError> {
    writer
        .write(content)
        .map_err(ClipOperationError::from_write)
}

/// 같은 식별자가 다른 원본이나 생성 시각의 클립으로 교체되었는지 판정
fn is_same_clip(updated: &ClipValue, clip: &ClipValue) -> bool {
    updated.id == clip.id
        && updated.content == clip.content
        && updated.created_at == clip.created_at
}
