use std::collections::HashSet;
use std::sync::{Arc, Mutex, MutexGuard, PoisonError};

use super::error::ClipOperationError;
use super::platform::{
    ClipCancellationSource, ClipCodecError, ClipImageCoder, ClipImagePropertiesValue,
    ClipImageValue,
};
use super::{now, NO_RANDOM};
use crate::image_files::{ClipImageFiles, ClipImageFilesError};
use crate::store::{ClipStore, ClipStoreError, ClipValue};
use crate::uuid_form::new_uuid;
use crate::ClipContentValue;

const PREVIEW_PIXEL_DIMENSION: i64 = 1600;

/// 호스트 내려받기 상한과 같은 원본 크기 상한
const MAXIMUM_DOWNLOAD_BYTE_COUNT: u64 = 20 * 1024 * 1024;

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
    codec: Arc<dyn ClipImageCoder>,
    /// 작업 순서이며 내려받는 중인 파일 식별자를 함께 보호
    order: Mutex<HashSet<String>>,
}

#[uniffi::export]
impl ClipImageOperations {
    #[uniffi::constructor]
    pub fn open(
        store: Arc<ClipStore>,
        root: String,
        codec: Arc<dyn ClipImageCoder>,
    ) -> Result<Arc<Self>, ClipOperationError> {
        Ok(Arc::new(Self {
            store,
            files: ClipImageFiles::open(root)?,
            codec,
            order: Mutex::new(HashSet::new()),
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
    /// 같은 인스턴스가 내려받는 중인 폴더는 건너뜀
    /// 본 앱이 `ShareInboxImages`에서 실행하면 저장 중인 파일을 지울 수 있음
    pub fn recover_pending_cleanup(
        &self,
        cancellation: Arc<dyn ClipCancellationSource>,
    ) -> Result<Vec<String>, ClipOperationError> {
        let order = self.lock();
        check(&cancellation)?;
        let mut candidates = self.files.pending_file_ids()?;
        candidates.retain(|file_id| !order.contains(file_id));
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

    /// 패닉 뒤에도 내려받기 예약은 각 예약의 정리가 지키므로 잠금을 계속 사용
    pub(super) fn lock(&self) -> MutexGuard<'_, HashSet<String>> {
        self.order.lock().unwrap_or_else(PoisonError::into_inner)
    }

    /// 내려받을 폴더를 만들고 복구 대상에서 제외
    pub(super) fn reserve_download(
        &self,
        cancellation: &Arc<dyn ClipCancellationSource>,
    ) -> Result<ClipDownloadReservation<'_>, ClipOperationError> {
        let mut order = self.lock();
        check(cancellation)?;
        let (file_id, path) = self.files.reserve()?;
        order.insert(file_id.clone());
        Ok(ClipDownloadReservation {
            images: self,
            file_id,
            path,
            is_finished: false,
        })
    }

    /// 내려받은 파일을 검증해 원본으로 확정하고 이미지 클립을 추가
    /// 이미지가 아니면 None
    /// 저장하지 못하면 폴더를 지우고 정리 표시 해제 실패는 다음 복구가 처리
    /// 클립 추가 확정 뒤에는 취소를 확인하지 않음
    pub(super) fn adopt_download(
        &self,
        mut reservation: ClipDownloadReservation<'_>,
        memo: String,
        cancellation: &Arc<dyn ClipCancellationSource>,
    ) -> Result<Option<ClipValue>, ClipOperationError> {
        let mut order = self.lock();
        reservation.is_finished = true;
        order.remove(&reservation.file_id);
        let adopted = self.adopt_locked(&reservation.file_id, memo, cancellation);
        if !matches!(adopted, Ok(Some(_))) {
            // 실패한 정리는 정리 표시가 남은 폴더로 다음 복구가 처리
            let _ = self.files.delete(&reservation.file_id);
        }
        adopted
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

    /// 잠금을 쥔 호출자 전용
    fn adopt_locked(
        &self,
        file_id: &str,
        memo: String,
        cancellation: &Arc<dyn ClipCancellationSource>,
    ) -> Result<Option<ClipValue>, ClipOperationError> {
        check(cancellation)?;
        let byte_count = self.files.adopt(file_id, MAXIMUM_DOWNLOAD_BYTE_COUNT)?;
        let path = self.files.validated_original_path(file_id, byte_count)?;
        let properties = match self.codec.properties(path) {
            Ok(properties) => properties,
            Err(ClipCodecError::Corrupted) => return Ok(None),
            Err(error) => return Err(ClipOperationError::from_codec(error, file_id)),
        };
        check(cancellation)?;
        let draft = new_draft()?;
        let clip = ClipValue {
            id: draft.id,
            content: ClipContentValue::Image {
                file_id: file_id.to_string(),
                content_type: properties.content_type,
                pixel_width: properties.pixel_width,
                pixel_height: properties.pixel_height,
                byte_count,
            },
            name: None,
            pinned_at: None,
            memo: Some(memo),
            created_at: draft.created_at,
            last_used_at: None,
        };
        self.store.insert(clip.clone())?;
        // 해제하지 못한 정리 표시는 참조된 폴더라 다음 복구가 표시만 지움
        let _ = self.files.finish_pending(file_id);
        Ok(Some(clip))
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

/// 내려받는 동안 복구가 지우지 않도록 예약한 폴더
/// 확정하지 않고 사라지면 폴더를 지우고 예약을 풂
pub(super) struct ClipDownloadReservation<'a> {
    images: &'a ClipImageOperations,
    file_id: String,
    pub(super) path: String,
    is_finished: bool,
}

impl Drop for ClipDownloadReservation<'_> {
    fn drop(&mut self) {
        if self.is_finished {
            return;
        }
        let mut order = self.images.lock();
        order.remove(&self.file_id);
        let _ = self.images.files.delete(&self.file_id);
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
