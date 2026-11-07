use std::sync::Arc;

use super::error::ClipOperationError;
use super::image::{check, ClipImageOperations};
use super::platform::{ClipCancellationSource, ClipDownloadError, ClipImageDownloader};
use super::{now, NO_RANDOM};
use crate::share_url::{image_url, response_kind, ShareResponseKind};
use crate::store::ClipValue;
use crate::uuid_form::new_uuid;
use crate::whitespace::trim;
use crate::{content, ClipContentValue};

#[derive(Clone, Debug, PartialEq, uniffi::Enum)]
pub enum ClipShareSaveValue {
    Saved { clip: ClipValue },
    Empty,
}

/// 공유받은 텍스트의 저장 순서
/// 이미지 첨부는 `ClipImageOperations.save_image`가 저장
/// 저장소는 `images`의 것을 써서 서로 다른 저장소가 섞이지 않음
#[derive(uniffi::Object)]
pub struct ClipShareOperations {
    images: Arc<ClipImageOperations>,
}

#[uniffi::export]
impl ClipShareOperations {
    #[uniffi::constructor]
    pub fn new(images: Arc<ClipImageOperations>) -> Arc<Self> {
        Arc::new(Self { images })
    }

    /// 공백뿐이면 `Empty`
    /// 내려받기를 허용했고 이미지 주소이면 내려받아 주소를 메모로 둔 이미지 클립으로 저장
    /// 내려받기나 이미지 판정에 실패하면 같은 문자열을 제목을 이름으로 둔 텍스트 클립으로 저장
    /// 내려받는 동안 코어 잠금을 쥐지 않음
    /// 저장 확정 뒤에는 취소를 확인하지 않음
    pub fn save_text(
        &self,
        text: String,
        title: Option<String>,
        allows_download: bool,
        downloader: Arc<dyn ClipImageDownloader>,
        cancellation: Arc<dyn ClipCancellationSource>,
    ) -> Result<ClipShareSaveValue, ClipOperationError> {
        if !content::is_text_valid(&text) {
            return Ok(ClipShareSaveValue::Empty);
        }
        if let Some(url) = allows_download.then(|| image_url(&text)).flatten() {
            if let Some(clip) = self.save_download(url, &downloader, &cancellation)? {
                return Ok(ClipShareSaveValue::Saved { clip });
            }
        }
        check(&cancellation)?;
        let clip = ClipValue {
            id: new_uuid().ok_or(NO_RANDOM)?,
            content: ClipContentValue::Text { text },
            name: title
                .map(|title| trim(&title).to_string())
                .filter(|title| !title.is_empty()),
            pinned_at: None,
            memo: None,
            created_at: now(),
            last_used_at: None,
        };
        self.images.store().insert(clip.clone())?;
        Ok(ClipShareSaveValue::Saved { clip })
    }
}

impl ClipShareOperations {
    /// 텍스트로 저장해야 하면 None
    fn save_download(
        &self,
        url: String,
        downloader: &Arc<dyn ClipImageDownloader>,
        cancellation: &Arc<dyn ClipCancellationSource>,
    ) -> Result<Option<ClipValue>, ClipOperationError> {
        let reservation = self.images.reserve_download(cancellation)?;
        match downloader.download(url.clone(), reservation.path.clone(), cancellation.clone()) {
            Ok(content_type)
                if response_kind(content_type.as_deref()) != ShareResponseKind::NotImage =>
            {
                self.images.adopt_download(reservation, url, cancellation)
            }
            Ok(_) => Ok(None),
            Err(ClipDownloadError::Cancelled) => Err(ClipOperationError::Cancelled),
            Err(_) => {
                drop(reservation);
                check(cancellation)?;
                Ok(None)
            }
        }
    }
}
