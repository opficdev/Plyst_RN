use std::sync::{Arc, Mutex, MutexGuard, PoisonError};

use super::error::ClipOperationError;
use super::platform::{
    ClipCancellationSource, ClipImageCoding, ClipImagePropertiesValue, ClipImageValue,
};
use super::{now, NO_RANDOM};
use crate::image_files::{ClipImageFiles, ClipImageFilesError};
use crate::store::{ClipStore, ClipStoreError, ClipValue};
use crate::uuid_form::new_uuid;
use crate::ClipContentValue;

const PREVIEW_PIXEL_DIMENSION: i64 = 1600;

/// 메타데이터 확정 뒤의 파일 정리 상태
#[derive(Clone, Debug, PartialEq, Eq, uniffi::Enum)]
pub enum ClipCleanupValue {
    Completed,
    Pending { file_id: String },
}

#[derive(Clone, Debug, PartialEq, uniffi::Record)]
pub struct ClipImageDraftValue {
    pub id: String,
    pub name: Option<String>,
    pub memo: Option<String>,
    pub pinned_at: Option<f64>,
    pub created_at: f64,
}

#[derive(Clone, Debug, PartialEq, uniffi::Record)]
pub struct ClipImageSavedValue {
    pub clip: ClipValue,
    pub cleanup: ClipCleanupValue,
}

/// 같은 루트의 이미지 쓰기와 복구를 하나의 인스턴스에서 조율
/// 별도 프로세스의 변경은 조율하지 않음
/// `ShareInboxImages`는 두 프로세스가 다룸
/// 저장과 복구는 Share Extension만 실행하고 본 앱은 읽기와 삭제만 실행
/// 파생 파일은 본 앱 이미지 루트에서만 만듦
#[derive(uniffi::Object)]
pub struct ClipImageOperations {
    store: Arc<ClipStore>,
    files: Arc<ClipImageFiles>,
    codec: Arc<dyn ClipImageCoding>,
    order: Mutex<()>,
}

#[uniffi::export]
impl ClipImageOperations {
    #[uniffi::constructor]
    pub fn open(
        store: Arc<ClipStore>,
        root: String,
        codec: Arc<dyn ClipImageCoding>,
    ) -> Result<Arc<Self>, ClipOperationError> {
        Ok(Arc::new(Self {
            store,
            files: ClipImageFiles::open(root)?,
            codec,
            order: Mutex::new(()),
        }))
    }

    /// 파일 저장, 클립 추가, `pending` 해제 순서
    /// 클립 추가 확정 뒤에는 취소를 확인하지 않음
    pub fn save_image(
        &self,
        data: &[u8],
        properties: ClipImagePropertiesValue,
        draft: ClipImageDraftValue,
        cancellation: Arc<dyn ClipCancellationSource>,
    ) -> Result<ClipImageSavedValue, ClipOperationError> {
        let _order = self.lock();
        check(&cancellation)?;
        let file_id = self.files.save(data)?;
        let clip = ClipValue {
            id: draft.id,
            content: ClipContentValue::Image {
                file_id: file_id.clone(),
                content_type: properties.content_type,
                pixel_width: properties.pixel_width,
                pixel_height: properties.pixel_height,
                byte_count: data.len() as i64,
            },
            name: draft.name,
            pinned_at: draft.pinned_at,
            memo: draft.memo,
            created_at: draft.created_at,
            last_used_at: None,
        };
        if let Err(error) = check(&cancellation) {
            let _ = self.files.delete(&file_id);
            return Err(error);
        }
        if let Err(error) = self.store.insert(clip.clone()) {
            let _ = self.files.delete(&file_id);
            return Err(error.into());
        }
        let cleanup = match self.files.finish_pending(&file_id) {
            Ok(()) => ClipCleanupValue::Completed,
            Err(_) => ClipCleanupValue::Pending { file_id },
        };
        Ok(ClipImageSavedValue { clip, cleanup })
    }

    /// 클립을 재조회하지 않고 전달받은 메타데이터와 원본을 대조
    /// 원본 읽기는 호스트가 같은 직렬 실행 안에서 돌려받은 경로로 수행
    pub fn load_image(
        &self,
        image: ClipImageValue,
        cancellation: Arc<dyn ClipCancellationSource>,
    ) -> Result<String, ClipOperationError> {
        let _order = self.lock();
        check(&cancellation)?;
        self.checked_original(&image)
    }

    /// 삭제와 직렬화하여 원본에서 미리보기 파일을 매번 다시 만듦
    pub fn make_preview(
        &self,
        image: ClipImageValue,
        cancellation: Arc<dyn ClipCancellationSource>,
    ) -> Result<String, ClipOperationError> {
        let _order = self.lock();
        check(&cancellation)?;
        let data = self.derived(&image, PREVIEW_PIXEL_DIMENSION)?;
        check(&cancellation)?;
        Ok(self.files.write_preview(&image.file_id, &data)?)
    }

    /// 삭제와 직렬화하여 요청한 크기의 썸네일 파일을 매번 다시 만듦
    pub fn make_thumbnail(
        &self,
        image: ClipImageValue,
        maximum_pixel_dimension: i64,
        cancellation: Arc<dyn ClipCancellationSource>,
    ) -> Result<String, ClipOperationError> {
        let _order = self.lock();
        check(&cancellation)?;
        let data = self.derived(&image, maximum_pixel_dimension)?;
        check(&cancellation)?;
        Ok(self
            .files
            .write_thumbnail(&image.file_id, maximum_pixel_dimension, &data)?)
    }

    /// `pending` 표시, 클립 삭제, 파일 정리 순서
    /// 클립 삭제가 확정되면 정리 실패와 취소는 정리 보류로만 돌려줌
    pub fn delete_clip(
        &self,
        id: String,
        cancellation: Arc<dyn ClipCancellationSource>,
    ) -> Result<ClipCleanupValue, ClipOperationError> {
        let _order = self.lock();
        check(&cancellation)?;
        let Some(clip) = self.store.fetch(id.clone())? else {
            return Err(ClipStoreError::NotFound { id }.into());
        };
        let file_id = image_file_id(&clip);
        if let Some(file_id) = file_id {
            self.files.mark_pending(file_id)?;
        }
        check(&cancellation)?;
        self.store.delete(id)?;
        Ok(match file_id {
            Some(file_id) => self.clean_after_commit(file_id, &cancellation),
            None => ClipCleanupValue::Completed,
        })
    }

    /// 이번에 정리하지 못한 파일 식별자만 돌려줌
    /// 조회에 실패하면 후보를 바꾸지 않고 오류를 돌려줌
    /// 본 앱이 `ShareInboxImages`에서 실행하면 저장 중인 파일을 지울 수 있음
    pub fn recover_pending_cleanup(
        &self,
        cancellation: Arc<dyn ClipCancellationSource>,
    ) -> Result<Vec<String>, ClipOperationError> {
        let _order = self.lock();
        check(&cancellation)?;
        let candidates = self.files.pending_file_ids()?;
        if candidates.is_empty() {
            return Ok(Vec::new());
        }
        check(&cancellation)?;
        let references = self.store.image_file_ids()?;
        Ok(candidates
            .into_iter()
            .filter(|file_id| self.clean(file_id, references.contains(file_id)).is_err())
            .collect())
    }
}

impl ClipImageOperations {
    pub(super) fn store(&self) -> &ClipStore {
        &self.store
    }

    /// 패닉 뒤에도 지키는 상태가 없으므로 잠금을 계속 사용
    pub(super) fn lock(&self) -> MutexGuard<'_, ()> {
        self.order.lock().unwrap_or_else(PoisonError::into_inner)
    }

    /// 잠금을 쥔 호출자 전용
    pub(super) fn checked_original(
        &self,
        image: &ClipImageValue,
    ) -> Result<String, ClipOperationError> {
        let path = self
            .files
            .validated_original_path(&image.file_id, image.byte_count)
            .map_err(|error| match error {
                ClipImageFilesError::SizeMismatch { file_id } => {
                    ClipOperationError::CorruptedImage { file_id }
                }
                error => error.into(),
            })?;
        let properties = self
            .codec
            .properties(path.clone())
            .map_err(|error| ClipOperationError::from_codec(error, &image.file_id))?;
        if properties.content_type != image.content_type
            || properties.pixel_width != image.pixel_width
            || properties.pixel_height != image.pixel_height
        {
            return Err(ClipOperationError::CorruptedImage {
                file_id: image.file_id.clone(),
            });
        }
        Ok(path)
    }

    /// 원본을 메모리에 모두 올리지 않고 플랫폼 코덱으로 축소
    fn derived(
        &self,
        image: &ClipImageValue,
        maximum_pixel_dimension: i64,
    ) -> Result<Vec<u8>, ClipOperationError> {
        if maximum_pixel_dimension <= 0 {
            return Err(ClipImageFilesError::ReadFailed.into());
        }
        let path = self
            .files
            .validated_original_path(&image.file_id, image.byte_count)?;
        self.codec
            .thumbnail(path, image.clone(), maximum_pixel_dimension)
            .map_err(|error| ClipOperationError::from_codec(error, &image.file_id))
    }

    fn clean_after_commit(
        &self,
        file_id: &str,
        cancellation: &Arc<dyn ClipCancellationSource>,
    ) -> ClipCleanupValue {
        let cleaned = check(cancellation)
            .and_then(|()| Ok(self.store.image_file_ids()?))
            .and_then(|references| Ok(self.clean(file_id, references.contains(file_id))?));
        match cleaned {
            Ok(()) => ClipCleanupValue::Completed,
            Err(_) => ClipCleanupValue::Pending {
                file_id: file_id.to_string(),
            },
        }
    }

    fn clean(&self, file_id: &str, is_referenced: bool) -> Result<(), ClipImageFilesError> {
        if is_referenced {
            self.files.finish_pending(file_id)
        } else {
            self.files.delete(file_id)
        }
    }
}

pub(super) fn check(
    cancellation: &Arc<dyn ClipCancellationSource>,
) -> Result<(), ClipOperationError> {
    if cancellation.is_cancelled() {
        Err(ClipOperationError::Cancelled)
    } else {
        Ok(())
    }
}

fn image_file_id(clip: &ClipValue) -> Option<&str> {
    match &clip.content {
        ClipContentValue::Image { file_id, .. } => Some(file_id),
        ClipContentValue::Text { .. } => None,
    }
}

/// 호출자가 식별자와 시각을 주지 않는 저장의 초안
pub(super) fn new_draft() -> Result<ClipImageDraftValue, ClipOperationError> {
    Ok(ClipImageDraftValue {
        id: new_uuid().ok_or(NO_RANDOM)?,
        name: None,
        memo: None,
        pinned_at: None,
        created_at: now(),
    })
}
