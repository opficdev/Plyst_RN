use std::fmt;

use super::platform::{ClipCodecError, ClipboardWriteError};
use crate::image_files::ClipImageFilesError;
use crate::store::ClipStoreError;

/// 작업 순서의 실패
/// 값과 경로를 담지 않고 원인 분류만 전달
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Error)]
pub enum ClipOperationError {
    Cancelled,
    CorruptedImage { file_id: String },
    ClipboardWriteFailed,
    Storage { error: ClipStoreError },
    Files { error: ClipImageFilesError },
}

impl fmt::Display for ClipOperationError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        fmt::Debug::fmt(self, formatter)
    }
}

impl std::error::Error for ClipOperationError {}

impl From<ClipStoreError> for ClipOperationError {
    fn from(error: ClipStoreError) -> Self {
        Self::Storage { error }
    }
}

impl From<ClipImageFilesError> for ClipOperationError {
    fn from(error: ClipImageFilesError) -> Self {
        Self::Files { error }
    }
}

impl ClipOperationError {
    /// 코덱 오류의 코어 표현
    /// 손상 판정에는 대상 파일 식별자를 붙임
    pub(super) fn from_codec(error: ClipCodecError, file_id: &str) -> Self {
        match error {
            ClipCodecError::Cancelled => Self::Cancelled,
            ClipCodecError::Corrupted => Self::CorruptedImage {
                file_id: file_id.to_string(),
            },
            ClipCodecError::ReadFailed | ClipCodecError::Unexpected => Self::Files {
                error: ClipImageFilesError::ReadFailed,
            },
        }
    }

    /// 클립보드 쓰기는 시작 전 실패만 이 값으로 돌아옴
    pub(super) fn from_write(error: ClipboardWriteError) -> Self {
        match error {
            ClipboardWriteError::Cancelled => Self::Cancelled,
            ClipboardWriteError::ReadFailed => Self::Files {
                error: ClipImageFilesError::ReadFailed,
            },
            ClipboardWriteError::Unexpected => Self::ClipboardWriteFailed,
        }
    }
}
