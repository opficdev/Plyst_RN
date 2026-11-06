use std::fmt;

use rusqlite::ffi::ErrorCode;

/// 저장소 오류 여섯 분류
/// SQL과 저장값은 담지 않고 SQLite 숫자 코드만 전달
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Error)]
pub enum ClipStoreError {
    DuplicateId { id: String },
    NotFound { id: String },
    InvalidContent,
    ReadFailed { code: i32, extended_code: i32 },
    WriteFailed { code: i32, extended_code: i32 },
    CorruptedData { code: i32, extended_code: i32 },
}

impl fmt::Display for ClipStoreError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        fmt::Debug::fmt(self, formatter)
    }
}

impl std::error::Error for ClipStoreError {}

#[derive(Clone, Copy)]
pub(crate) enum Fallback {
    Read,
    Write,
}

impl ClipStoreError {
    /// 행 해석 실패, 모르는 마이그레이션, 지원 범위를 넘는 버전
    pub(crate) fn corrupted() -> Self {
        Self::CorruptedData {
            code: 0,
            extended_code: 0,
        }
    }

    pub(crate) fn classify(error: rusqlite::Error, fallback: Fallback) -> Self {
        let (code, extended_code) = match &error {
            rusqlite::Error::SqliteFailure(failure, _) => {
                if matches!(
                    failure.code,
                    ErrorCode::DatabaseCorrupt | ErrorCode::NotADatabase
                ) {
                    return Self::CorruptedData {
                        code: failure.extended_code & 0xff,
                        extended_code: failure.extended_code,
                    };
                }
                (failure.extended_code & 0xff, failure.extended_code)
            }
            rusqlite::Error::FromSqlConversionFailure(..)
            | rusqlite::Error::InvalidColumnType(..)
            | rusqlite::Error::Utf8Error(..)
            | rusqlite::Error::IntegralValueOutOfRange(..) => return Self::corrupted(),
            _ => (0, 0),
        };
        match fallback {
            Fallback::Read => Self::ReadFailed {
                code,
                extended_code,
            },
            Fallback::Write => Self::WriteFailed {
                code,
                extended_code,
            },
        }
    }
}
