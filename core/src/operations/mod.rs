//! 파일, 데이터베이스, 클립보드를 함께 쓰는 작업의 순서
//! 잠금 순서는 플랫폼 클립보드 직렬화, `order`, `ClipStore` 연결 순서
//! 외부 구현은 앞선 잠금을 다시 잡지 않음
//! 취소는 판정 지점에서만 읽고 시작한 호출을 중단하지 않음

mod clipboard;
mod error;
mod image;
mod platform;

use std::time::{SystemTime, UNIX_EPOCH};

use crate::store::ClipStoreError;

pub use clipboard::{
    ClipboardCopyValue, ClipboardOperations, ClipboardSaveValue, ClipboardUsageFailureValue,
};
pub use error::ClipOperationError;
pub use image::{ClipCleanupValue, ClipImageDraftValue, ClipImageOperations, ClipImageSavedValue};
pub use platform::{
    ClipCancellationSource, ClipCodecError, ClipImageCoding, ClipImagePropertiesValue,
    ClipImageValue, ClipboardWriteError, ClipboardWriteOutcome, ClipboardWriteValue,
    ClipboardWriting,
};

/// 시스템 난수를 읽지 못해 식별자를 만들 수 없을 때의 쓰기 실패
const NO_RANDOM: ClipStoreError = ClipStoreError::WriteFailed {
    code: 0,
    extended_code: 0,
};

/// Unix 기준 시각과 2001-01-01 기준 시각의 차이
const REFERENCE_DATE_OFFSET: f64 = 978_307_200.0;

/// 현재 시각의 2001-01-01 기준 초
fn now() -> f64 {
    let elapsed = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default();
    elapsed.as_secs_f64() - REFERENCE_DATE_OFFSET
}
