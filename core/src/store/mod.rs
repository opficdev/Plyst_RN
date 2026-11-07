mod error;
mod schema;
mod value;
mod wire;

use std::collections::HashSet;
use std::fs;
use std::path::Path;
use std::sync::{Arc, Mutex, MutexGuard, PoisonError};
use std::time::Duration;

use rusqlite::{params, Connection, OptionalExtension, Transaction, TransactionBehavior};

pub use crate::ClipContentValue;
pub use error::ClipStoreError;
use error::Fallback;
use value::{stored_id, COLUMNS};
pub use value::{ClipSortOrderValue, ClipUpdateResult, ClipUpdateValue, ClipValue};

use crate::{guard, search_history, sort};

const BUSY_TIMEOUT: Duration = Duration::from_secs(5);

/// iOS 시스템 SQLite의 WAL 파일 한도
#[cfg(not(target_os = "android"))]
const WAL_SIZE: &str = "PRAGMA journal_size_limit = 32768;";

/// Android 시스템 SQLite와 같은 값
/// 두 값을 함께 써야 쓰기 시간이 기존 Android 저장소와 같아짐
#[cfg(target_os = "android")]
const WAL_SIZE: &str = "PRAGMA wal_autocheckpoint = 100;
    PRAGMA journal_size_limit = 524288;";

fn read_failed(error: rusqlite::Error) -> ClipStoreError {
    ClipStoreError::classify(error, Fallback::Read)
}

fn write_failed(error: rusqlite::Error) -> ClipStoreError {
    ClipStoreError::classify(error, Fallback::Write)
}

/// 커밋된 클립 변경
#[derive(Debug, Clone, PartialEq, uniffi::Enum)]
pub enum ClipChangeValue {
    Inserted { clip: ClipValue },
    Updated { clip: ClipValue },
    Deleted { id: String },
}

/// 연결 잠금을 쥔 채 커밋 순서로 호출
/// 구현은 값만 전달하고 코어를 다시 호출하거나 대기하지 않음
#[uniffi::export(foreign)]
pub trait ClipChangeListener: Send + Sync {
    fn changed(&self, change: ClipChangeValue);
}

/// 클립과 최근 검색어 영구 저장
/// 연결 잠금이 이미지 작업과 저장소 Service의 호출을 함께 직렬화
#[derive(uniffi::Object)]
pub struct ClipStore {
    connection: Mutex<Connection>,
    listener: Arc<dyn ClipChangeListener>,
}

#[uniffi::export]
impl ClipStore {
    #[uniffi::constructor]
    pub fn open(
        path: String,
        listener: Arc<dyn ClipChangeListener>,
    ) -> Result<Arc<Self>, ClipStoreError> {
        if let Some(directory) = Path::new(&path).parent() {
            fs::create_dir_all(directory).map_err(|_| ClipStoreError::WriteFailed {
                code: 0,
                extended_code: 0,
            })?;
        }
        let mut connection = Connection::open(&path).map_err(read_failed)?;
        configure(&connection)?;
        schema::migrate(&mut connection)?;
        Ok(Arc::new(Self {
            connection: Mutex::new(connection),
            listener,
        }))
    }

    /// 목록은 필드별 UniFFI 직렬화 대신 한 버퍼로 전달
    /// 형식은 wire 모듈이 소유
    pub fn fetch_all_encoded(&self, order: ClipSortOrderValue) -> Result<Vec<u8>, ClipStoreError> {
        Ok(wire::encoded(&self.fetch_all(order)?))
    }

    pub fn fetch(&self, id: String) -> Result<Option<ClipValue>, ClipStoreError> {
        let connection = self.lock();
        find(&connection, &stored_key(&id)?).map_err(|failure| failure.into_error(Fallback::Read))
    }

    pub fn insert(&self, clip: ClipValue) -> Result<(), ClipStoreError> {
        if !clip.is_valid() {
            return Err(ClipStoreError::InvalidContent);
        }
        let id = stored_key(&clip.id)?;
        self.write_reporting(|transaction| {
            if find(transaction, &id).map_err(|failure| failure.into_error(Fallback::Write))?.is_some() {
                return Err(ClipStoreError::DuplicateId { id: clip.id.clone() });
            }
            let (text, file_id, content_type, width, height, count) = content_columns(&clip.content);
            transaction
                .execute(
                    &format!("INSERT INTO clips ({COLUMNS}) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13)"),
                    params![id, kind(&clip.content), text, file_id, content_type, width, height, count, clip.name, clip.pinned_at, clip.memo, clip.created_at, clip.last_used_at],
                )
                .map_err(write_failed)?;
            Ok(((), Some(ClipChangeValue::Inserted { clip: clip.clone() })))
        })
    }

    pub fn update(
        &self,
        id: String,
        change: ClipUpdateValue,
    ) -> Result<ClipUpdateResult, ClipStoreError> {
        let key = stored_key(&id)?;
        self.write_reporting(|transaction| {
            let current = find(transaction, &key)
                .map_err(|failure| failure.into_error(Fallback::Write))?
                .ok_or_else(|| ClipStoreError::NotFound { id: id.clone() })?;
            let updated = current.applying(&change);
            if updated == current {
                return Ok((ClipUpdateResult { clip: current, changed: false }, None));
            }
            if !updated.is_valid() {
                return Err(ClipStoreError::InvalidContent);
            }
            transaction
                .execute(
                    "UPDATE clips SET name = ?1, pinnedAt = ?2, memo = ?3, lastUsedAt = ?4 WHERE id = ?5",
                    params![updated.name, updated.pinned_at, updated.memo, updated.last_used_at, key],
                )
                .map_err(write_failed)?;
            let report = ClipChangeValue::Updated { clip: updated.clone() };
            Ok((ClipUpdateResult { clip: updated, changed: true }, Some(report)))
        })
    }

    pub fn delete(&self, id: String) -> Result<(), ClipStoreError> {
        let key = stored_key(&id)?;
        self.write_reporting(|transaction| {
            if find(transaction, &key)
                .map_err(|failure| failure.into_error(Fallback::Write))?
                .is_none()
            {
                return Err(ClipStoreError::NotFound { id: id.clone() });
            }
            transaction
                .execute("DELETE FROM clips WHERE id = ?1", [&key])
                .map_err(write_failed)?;
            Ok((
                (),
                Some(ClipChangeValue::Deleted {
                    id: id.to_ascii_uppercase(),
                }),
            ))
        })
    }

    pub fn fetch_search_terms(&self) -> Result<Vec<String>, ClipStoreError> {
        let connection = self.lock();
        search_terms(&connection, Fallback::Read)
    }

    pub fn record_search_term(&self, query: String) -> Result<Vec<String>, ClipStoreError> {
        self.replace_search_terms(|terms| search_history::recording(terms, query))
    }

    pub fn remove_search_term(&self, term: String) -> Result<Vec<String>, ClipStoreError> {
        self.replace_search_terms(|terms| search_history::removing(terms, &term))
    }

    /// 저장값을 해석하지 않고 모두 제거
    pub fn remove_all_search_terms(&self) -> Result<(), ClipStoreError> {
        self.write(|transaction| {
            transaction
                .execute("DELETE FROM clipSearchTerms", [])
                .map_err(write_failed)?;
            Ok(())
        })
    }
}

impl ClipStore {
    pub fn fetch_all(&self, order: ClipSortOrderValue) -> Result<Vec<ClipValue>, ClipStoreError> {
        let connection = self.lock();
        let mut statement = connection
            .prepare_cached(&format!("SELECT {COLUMNS} FROM clips"))
            .map_err(read_failed)?;
        let mut rows = statement.query([]).map_err(read_failed)?;
        let mut clips = Vec::new();
        while let Some(row) = rows.next().map_err(read_failed)? {
            clips.push(ClipValue::from_row(row)?);
        }
        match order {
            ClipSortOrderValue::CreatedAt => Ok(sorted(clips)),
        }
    }

    /// 이미지 클립이 참조하는 파일 식별자
    /// 행을 fetch_all과 같게 검증하므로 손상된 행에서 같은 오류를 돌려줌
    pub fn image_file_ids(&self) -> Result<HashSet<String>, ClipStoreError> {
        let connection = self.lock();
        let mut statement = connection
            .prepare_cached(&format!("SELECT {COLUMNS} FROM clips"))
            .map_err(read_failed)?;
        let mut rows = statement.query([]).map_err(read_failed)?;
        let mut ids = HashSet::new();
        while let Some(row) = rows.next().map_err(read_failed)? {
            if let ClipContentValue::Image { file_id, .. } = ClipValue::from_row(row)?.content {
                ids.insert(file_id);
            }
        }
        Ok(ids)
    }

    /// 패닉 뒤에도 트랜잭션은 Drop에서 롤백되었으므로 연결을 계속 사용
    fn lock(&self) -> MutexGuard<'_, Connection> {
        self.connection
            .lock()
            .unwrap_or_else(PoisonError::into_inner)
    }

    /// 읽기에서 쓰기로 승격하다 대기 없이 BUSY가 되지 않도록 즉시 잠금으로 시작
    fn write<Value>(
        &self,
        operation: impl FnOnce(&Transaction<'_>) -> Result<Value, ClipStoreError>,
    ) -> Result<Value, ClipStoreError> {
        let mut connection = self.lock();
        let transaction = connection
            .transaction_with_behavior(TransactionBehavior::Immediate)
            .map_err(write_failed)?;
        let value = operation(&transaction)?;
        transaction.commit().map_err(write_failed)?;
        Ok(value)
    }

    /// 변경 알림이 커밋 순서를 따르도록 연결 잠금을 쥔 채 알림
    /// 커밋 뒤의 알림 실패는 확정된 쓰기의 결과를 바꾸지 않음
    fn write_reporting<Value>(
        &self,
        operation: impl FnOnce(
            &Transaction<'_>,
        ) -> Result<(Value, Option<ClipChangeValue>), ClipStoreError>,
    ) -> Result<Value, ClipStoreError> {
        let mut connection = self.lock();
        let transaction = connection
            .transaction_with_behavior(TransactionBehavior::Immediate)
            .map_err(write_failed)?;
        let (value, change) = operation(&transaction)?;
        transaction.commit().map_err(write_failed)?;
        if let Some(change) = change {
            guard((), || self.listener.changed(change));
        }
        Ok(value)
    }

    /// 읽기, 규칙 적용, 전체 교체를 하나의 트랜잭션으로 처리
    /// 결과가 같으면 쓰지 않음
    fn replace_search_terms(
        &self,
        change: impl FnOnce(Vec<String>) -> Vec<String>,
    ) -> Result<Vec<String>, ClipStoreError> {
        self.write(|transaction| {
            let current = search_terms(transaction, Fallback::Write)?;
            let updated = change(current.clone());
            if updated == current {
                return Ok(current);
            }
            transaction
                .execute("DELETE FROM clipSearchTerms", [])
                .map_err(write_failed)?;
            for (position, term) in updated.iter().enumerate() {
                transaction
                    .execute(
                        "INSERT INTO clipSearchTerms (position, term) VALUES (?1, ?2)",
                        params![position as i64, term],
                    )
                    .map_err(write_failed)?;
            }
            Ok(updated)
        })
    }
}

/// iOS 시스템 SQLite의 기본값을 명시해 내구성과 메모리 사용을 유지
/// 체크포인트 fullfsync는 iPhone17,1 iOS 27.2 라이브러리의 컴파일 옵션 값
fn configure(connection: &Connection) -> Result<(), ClipStoreError> {
    // WAL 전환도 잠금을 기다리도록 다른 PRAGMA보다 먼저 설정
    connection.busy_timeout(BUSY_TIMEOUT).map_err(read_failed)?;
    let mode: String = connection
        .query_row("PRAGMA journal_mode = WAL", [], |row| row.get(0))
        .map_err(read_failed)?;
    if mode != "wal" {
        return Err(ClipStoreError::ReadFailed {
            code: 0,
            extended_code: 0,
        });
    }
    connection
        .execute_batch(
            "PRAGMA synchronous = 2;
            PRAGMA checkpoint_fullfsync = 1;
            PRAGMA cache_size = 128;",
        )
        .map_err(read_failed)?;
    connection.execute_batch(WAL_SIZE).map_err(read_failed)
}

enum FindFailure {
    Sqlite(rusqlite::Error),
    Decode(ClipStoreError),
}

impl FindFailure {
    fn into_error(self, fallback: Fallback) -> ClipStoreError {
        match self {
            Self::Sqlite(error) => ClipStoreError::classify(error, fallback),
            Self::Decode(error) => error,
        }
    }
}

fn find(connection: &Connection, id: &str) -> Result<Option<ClipValue>, FindFailure> {
    let mut statement = connection
        .prepare_cached(&format!("SELECT {COLUMNS} FROM clips WHERE id = ?1"))
        .map_err(FindFailure::Sqlite)?;
    let row = statement
        .query_row([id], |row| Ok(ClipValue::from_row(row)))
        .optional()
        .map_err(FindFailure::Sqlite)?;
    row.transpose().map_err(FindFailure::Decode)
}

fn search_terms(
    connection: &Connection,
    fallback: Fallback,
) -> Result<Vec<String>, ClipStoreError> {
    let failed = |error| ClipStoreError::classify(error, fallback);
    let mut statement = connection
        .prepare_cached("SELECT term FROM clipSearchTerms ORDER BY position")
        .map_err(failed)?;
    let terms = statement
        .query_map([], |row| row.get::<_, String>(0))
        .map_err(failed)?
        .collect::<Result<Vec<_>, _>>()
        .map_err(failed)?;
    search_history::restored(terms).ok_or_else(ClipStoreError::corrupted)
}

/// 생성 시각과 식별자 순서 규칙은 sort 모듈이 소유
fn sorted(clips: Vec<ClipValue>) -> Vec<ClipValue> {
    let created_at: Vec<f64> = clips.iter().map(|clip| clip.created_at).collect();
    let ids: Vec<u8> = clips.iter().flat_map(|clip| id_bytes(&clip.id)).collect();
    let mut slots: Vec<Option<ClipValue>> = clips.into_iter().map(Some).collect();
    sort::order(&created_at, &ids)
        .into_iter()
        .filter_map(|index| slots[index as usize].take())
        .collect()
}

/// UUID 문자열의 16바이트 값
/// 형식은 stored_id가 보장
pub(crate) fn id_bytes(id: &str) -> [u8; 16] {
    let mut bytes = [0; 16];
    let digits = id.chars().filter_map(|digit| digit.to_digit(16));
    for (index, digit) in digits.enumerate() {
        bytes[index / 2] = bytes[index / 2] << 4 | digit as u8;
    }
    bytes
}

fn stored_key(id: &str) -> Result<String, ClipStoreError> {
    stored_id(id).ok_or(ClipStoreError::InvalidContent)
}

fn kind(content: &ClipContentValue) -> &'static str {
    match content {
        ClipContentValue::Text { .. } => "text",
        ClipContentValue::Image { .. } => "image",
    }
}

type ContentColumns<'a> = (
    Option<&'a str>,
    Option<String>,
    Option<&'a str>,
    Option<i64>,
    Option<i64>,
    Option<i64>,
);

fn content_columns(content: &ClipContentValue) -> ContentColumns<'_> {
    match content {
        ClipContentValue::Text { text } => (Some(text), None, None, None, None, None),
        ClipContentValue::Image {
            file_id,
            content_type,
            pixel_width,
            pixel_height,
            byte_count,
        } => (
            None,
            stored_id(file_id),
            Some(content_type),
            Some(*pixel_width),
            Some(*pixel_height),
            Some(*byte_count),
        ),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn pragma(connection: &Connection, name: &str) -> i64 {
        connection
            .pragma_query_value(None, name, |row| row.get(0))
            .unwrap()
    }

    #[test]
    fn connection_keeps_ios_durability_and_memory_settings() {
        let directory =
            std::env::temp_dir().join(format!("plyst-configure-{}", std::process::id()));
        std::fs::create_dir_all(&directory).unwrap();
        let connection = Connection::open(directory.join("clips.sqlite")).unwrap();
        configure(&connection).unwrap();
        let mode: String = connection
            .pragma_query_value(None, "journal_mode", |row| row.get(0))
            .unwrap();
        assert_eq!(mode, "wal");
        assert_eq!(pragma(&connection, "busy_timeout"), 5000);
        assert_eq!(pragma(&connection, "synchronous"), 2);
        assert_eq!(pragma(&connection, "checkpoint_fullfsync"), 1);
        assert_eq!(pragma(&connection, "journal_size_limit"), 32768);
        assert_eq!(pragma(&connection, "cache_size"), 128);
        std::fs::remove_dir_all(directory).unwrap();
    }

    #[test]
    fn bundled_sqlite_keeps_the_ios_value_size_limit() {
        let connection = Connection::open_in_memory().unwrap();
        let mut statement = connection.prepare("PRAGMA compile_options").unwrap();
        let options: Vec<String> = statement
            .query_map([], |row| row.get(0))
            .unwrap()
            .map(Result::unwrap)
            .collect();
        assert!(options
            .iter()
            .any(|option| option == "MAX_LENGTH=2147483645"));
    }
}
