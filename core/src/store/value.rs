use rusqlite::types::FromSql;
use rusqlite::Row;

use super::error::ClipStoreError;
use crate::uuid_form::is_uuid_form;
use crate::{content, update, ClipContentValue, ClipIdentity};

pub(crate) const COLUMNS: &str = "id, kind, text, imageFileID, imageContentType, pixelWidth, pixelHeight, byteCount, name, pinnedAt, memo, createdAt, lastUsedAt";

/// 시각은 2001-01-01 기준 초
/// 밀리초로 줄이지 않아 iOS의 밀리초 미만 값을 보존
/// 식별자는 코어 공통 표기인 대문자 UUID 문자열
/// 소문자 저장 표기는 행 읽기와 SQL 바인딩에서만 사용
#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct ClipValue {
    pub id: String,
    pub content: ClipContentValue,
    pub name: Option<String>,
    pub pinned_at: Option<f64>,
    pub memo: Option<String>,
    pub created_at: f64,
    pub last_used_at: Option<f64>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum ClipSortOrderValue {
    CreatedAt,
}

#[derive(Debug, Clone, PartialEq, uniffi::Enum)]
pub enum ClipUpdateValue {
    Details {
        name: Option<String>,
        memo: Option<String>,
        is_pinned: bool,
        requested_at: f64,
    },
    LastUsedAt {
        date: f64,
        matching: Option<ClipIdentity>,
    },
}

#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct ClipUpdateResult {
    pub clip: ClipValue,
    pub changed: bool,
}

/// 36자 형식과 16진수만 허용하고 소문자로 통일
/// iOS 저장값이 소문자이므로 바인딩 값도 이 표기를 씀
pub(crate) fn stored_id(value: &str) -> Option<String> {
    is_uuid_form(value).then(|| value.to_ascii_lowercase())
}

/// 저장값을 경계 밖 표기로 변환
fn wire_id(value: &str) -> Result<String, ClipStoreError> {
    stored_id(value)
        .map(|id| id.to_ascii_uppercase())
        .ok_or_else(ClipStoreError::corrupted)
}

fn column<T: FromSql>(row: &Row<'_>, index: usize) -> Result<T, ClipStoreError> {
    row.get(index).map_err(|_| ClipStoreError::corrupted())
}

fn is_finite(value: Option<f64>) -> bool {
    value.is_none_or(f64::is_finite)
}

impl ClipValue {
    pub(crate) fn is_valid(&self) -> bool {
        let is_content_valid = match &self.content {
            ClipContentValue::Text { text } => content::is_text_valid(text),
            ClipContentValue::Image {
                content_type,
                pixel_width,
                pixel_height,
                byte_count,
                ..
            } => content::is_image_valid(content_type, *pixel_width, *pixel_height, *byte_count),
        };
        is_content_valid
            && self.created_at.is_finite()
            && is_finite(self.pinned_at)
            && is_finite(self.last_used_at)
    }

    /// 저장값이 규칙과 맞지 않으면 CorruptedData
    pub(crate) fn from_row(row: &Row<'_>) -> Result<Self, ClipStoreError> {
        let id: String = column(row, 0)?;
        let kind: String = column(row, 1)?;
        let text: Option<String> = column(row, 2)?;
        let image_file_id: Option<String> = column(row, 3)?;
        let image_content_type: Option<String> = column(row, 4)?;
        let pixel_width: Option<i64> = column(row, 5)?;
        let pixel_height: Option<i64> = column(row, 6)?;
        let byte_count: Option<i64> = column(row, 7)?;
        let content = match (
            kind.as_str(),
            text,
            image_file_id,
            image_content_type,
            pixel_width,
            pixel_height,
            byte_count,
        ) {
            ("text", Some(text), None, None, None, None, None) => ClipContentValue::Text { text },
            (
                "image",
                None,
                Some(file_id),
                Some(content_type),
                Some(pixel_width),
                Some(pixel_height),
                Some(byte_count),
            ) => ClipContentValue::Image {
                file_id: wire_id(&file_id)?,
                content_type,
                pixel_width,
                pixel_height,
                byte_count,
            },
            _ => return Err(ClipStoreError::corrupted()),
        };
        let clip = Self {
            id: wire_id(&id)?,
            content,
            name: column(row, 8)?,
            pinned_at: column(row, 9)?,
            memo: column(row, 10)?,
            created_at: column(row, 11)?,
            last_used_at: column(row, 12)?,
        };
        if clip.is_valid() {
            Ok(clip)
        } else {
            Err(ClipStoreError::corrupted())
        }
    }

    fn identity(&self) -> ClipIdentity {
        ClipIdentity {
            id: self.id.clone(),
            content: self.content.clone(),
            created_at: self.created_at,
        }
    }

    pub(crate) fn applying(&self, change: &ClipUpdateValue) -> Self {
        let mut updated = self.clone();
        match change {
            ClipUpdateValue::Details {
                name,
                memo,
                is_pinned,
                requested_at,
            } => {
                updated.name = name.clone();
                updated.memo = memo.clone();
                updated.pinned_at = update::pinned_at(self.pinned_at, *is_pinned, *requested_at);
            }
            ClipUpdateValue::LastUsedAt { date, matching } => {
                if let Some(expected) = matching {
                    if !update::usage_applies(&uppercased(expected), &self.identity()) {
                        return updated;
                    }
                }
                updated.last_used_at = Some(*date);
            }
        }
        updated
    }
}

/// 호출자가 어떤 표기로 넘겨도 사용 시각 비교가 건너뛰어지지 않도록 대문자로 통일
fn uppercased(identity: &ClipIdentity) -> ClipIdentity {
    let mut identity = identity.clone();
    identity.id.make_ascii_uppercase();
    if let ClipContentValue::Image { file_id, .. } = &mut identity.content {
        file_id.make_ascii_uppercase();
    }
    identity
}
