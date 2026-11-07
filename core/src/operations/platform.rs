//! 코어가 부르는 플랫폼 구현
//! 모두 동기 trait이고 코어는 비동기 함수를 내보내지 않음
//! 구현은 모든 플랫폼 예외를 선언된 오류로 바꿔 던져야 함
//! 선언되지 않은 실패는 코어에서 패닉이 되므로 `Unexpected`로 받음

use std::fmt;
use std::sync::Arc;

use uniffi::UnexpectedUniFFICallbackError;

#[derive(Clone, Debug, PartialEq, Eq, uniffi::Record)]
pub struct ClipImageValue {
    pub file_id: String,
    pub content_type: String,
    pub pixel_width: i64,
    pub pixel_height: i64,
    pub byte_count: i64,
}

#[derive(Clone, Debug, PartialEq, Eq, uniffi::Record)]
pub struct ClipImagePropertiesValue {
    pub content_type: String,
    pub pixel_width: i64,
    pub pixel_height: i64,
}

#[derive(Debug, Clone, PartialEq, Eq, uniffi::Error)]
pub enum ClipCodecError {
    Cancelled,
    Corrupted,
    ReadFailed,
    Unexpected,
}

impl fmt::Display for ClipCodecError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        fmt::Debug::fmt(self, formatter)
    }
}

impl std::error::Error for ClipCodecError {}

impl From<UnexpectedUniFFICallbackError> for ClipCodecError {
    fn from(_: UnexpectedUniFFICallbackError) -> Self {
        Self::Unexpected
    }
}

#[uniffi::export(foreign)]
pub trait ClipImageCoder: Send + Sync {
    fn properties(&self, path: String) -> Result<ClipImagePropertiesValue, ClipCodecError>;
    fn thumbnail(
        &self,
        path: String,
        image: ClipImageValue,
        maximum_pixel_dimension: i64,
    ) -> Result<Vec<u8>, ClipCodecError>;
}

#[derive(Clone, Debug, PartialEq, Eq, uniffi::Enum)]
pub enum ClipboardWriteValue {
    Text { text: String },
    Image { path: String, content_type: String },
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, uniffi::Enum)]
pub enum ClipboardWriteOutcome {
    Observed,
    NotObserved,
}

#[derive(Debug, Clone, PartialEq, Eq, uniffi::Error)]
pub enum ClipboardWriteError {
    Cancelled,
    ReadFailed,
    Unexpected,
}

impl fmt::Display for ClipboardWriteError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        fmt::Debug::fmt(self, formatter)
    }
}

impl std::error::Error for ClipboardWriteError {}

impl From<UnexpectedUniFFICallbackError> for ClipboardWriteError {
    fn from(_: UnexpectedUniFFICallbackError) -> Self {
        Self::Unexpected
    }
}

/// 오류는 쓰기를 시작하기 전에만 던짐
/// 쓰기 이후에는 관측 결과를 돌려줌
#[uniffi::export(foreign)]
pub trait ClipboardWriter: Send + Sync {
    fn write(
        &self,
        content: ClipboardWriteValue,
    ) -> Result<ClipboardWriteOutcome, ClipboardWriteError>;
}

#[uniffi::export(foreign)]
pub trait ClipCancellationSource: Send + Sync {
    fn is_cancelled(&self) -> bool;
}

#[derive(Debug, Clone, PartialEq, Eq, uniffi::Error)]
pub enum ClipDownloadError {
    Cancelled,
    Failed,
    Unexpected,
}

impl fmt::Display for ClipDownloadError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        fmt::Debug::fmt(self, formatter)
    }
}

impl std::error::Error for ClipDownloadError {}

impl From<UnexpectedUniFFICallbackError> for ClipDownloadError {
    fn from(_: UnexpectedUniFFICallbackError) -> Self {
        Self::Unexpected
    }
}

/// `url`의 응답 본문을 `path`에 새 파일로 쓰고 Content-Type 헤더 원문을 돌려줌
/// 파일이 이미 있으면 덮어쓰지 않고 실패
/// 상태 코드, 크기 상한, 시간 제한은 구현이 판정하고 응답 형식은 코어가 판정
/// 폴더와 파일의 정리는 코어가 맡으며 구현은 파일을 지우거나 옮기지 않음
/// 취소 상태를 읽으면 전송을 끊고 `Cancelled`를 던짐
#[uniffi::export(foreign)]
pub trait ClipImageDownloader: Send + Sync {
    fn download(
        &self,
        url: String,
        path: String,
        cancellation: Arc<dyn ClipCancellationSource>,
    ) -> Result<Option<String>, ClipDownloadError>;
}
