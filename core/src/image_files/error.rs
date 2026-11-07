use std::fmt;

/// 파일 경로와 이미지 내용을 담지 않는 오류
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Error)]
pub enum ClipImageFilesError {
    InvalidRoot,
    UnsafePath,
    NotFound { file_id: String },
    SizeMismatch { file_id: String },
    ReadFailed,
    WriteFailed,
    DeleteFailed,
}

impl fmt::Display for ClipImageFilesError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        fmt::Debug::fmt(self, formatter)
    }
}

impl std::error::Error for ClipImageFilesError {}
