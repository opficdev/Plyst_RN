use rusqlite::{Connection, OptionalExtension, Transaction, TransactionBehavior};

use super::error::{ClipStoreError, Fallback};

const LATEST_VERSION: i64 = 3;
const GRDB_TABLE: &str = "grdb_migrations";

/// 번호 순서가 적용 순서
/// 식별자는 GRDB가 기록한 이름
/// 3은 iOS 표에 효과가 없어 식별자가 없고 이전 빌드도 그대로 열 수 있음
const IDENTIFIERS: [(i64, &str); 2] = [(1, "CreateClips"), (2, "CreateClipSearchTerms")];

const CLIPS_BODY: &str = r#"("id" TEXT PRIMARY KEY NOT NULL, "kind" TEXT NOT NULL CHECK (("kind" = 'text') OR ("kind" = 'image')), "text" TEXT, "imageFileID" TEXT, "imageContentType" TEXT, "pixelWidth" INTEGER, "pixelHeight" INTEGER, "byteCount" INTEGER, "name" TEXT, "pinnedAt" REAL, "memo" TEXT, "createdAt" REAL NOT NULL, "lastUsedAt" REAL, CHECK ((("kind" = 'text') AND ("text" IS NOT NULL) AND ("imageFileID" IS NULL) AND ("imageContentType" IS NULL) AND ("pixelWidth" IS NULL) AND ("pixelHeight" IS NULL) AND ("byteCount" IS NULL)) OR (("kind" = 'image') AND ("text" IS NULL) AND ("imageFileID" IS NOT NULL) AND ("imageContentType" IS NOT NULL) AND ("pixelWidth" IS NOT NULL) AND (0 < "pixelWidth") AND ("pixelHeight" IS NOT NULL) AND (0 < "pixelHeight") AND ("byteCount" IS NOT NULL) AND (0 < "byteCount")))) STRICT"#;

const TERMS_BODY: &str = r#"("position" INTEGER PRIMARY KEY NOT NULL CHECK (0 <= "position"), "term" TEXT NOT NULL UNIQUE CHECK ("term" <> '')) STRICT"#;

fn write_failed(error: rusqlite::Error) -> ClipStoreError {
    ClipStoreError::classify(error, Fallback::Write)
}

fn user_version(connection: &Connection) -> Result<i64, rusqlite::Error> {
    connection.pragma_query_value(None, "user_version", |row| row.get(0))
}

fn has_grdb_table(connection: &Connection) -> Result<bool, rusqlite::Error> {
    Ok(connection
        .query_row(
            "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?1",
            [GRDB_TABLE],
            |_| Ok(()),
        )
        .optional()?
        .is_some())
}

/// 적용된 번호 목록
/// 이전 판단의 기준은 user_version과 grdb_migrations의 합집합
fn applied_versions(connection: &Connection) -> Result<Vec<i64>, ClipStoreError> {
    let version = user_version(connection).map_err(write_failed)?;
    if !(0..=LATEST_VERSION).contains(&version) {
        return Err(ClipStoreError::corrupted());
    }
    let mut applied: Vec<i64> = (1..=version).collect();
    if has_grdb_table(connection).map_err(write_failed)? {
        let mut statement = connection
            .prepare("SELECT identifier FROM grdb_migrations")
            .map_err(write_failed)?;
        let identifiers = statement
            .query_map([], |row| row.get::<_, String>(0))
            .map_err(write_failed)?;
        for identifier in identifiers {
            let identifier = identifier.map_err(write_failed)?;
            let Some((known, _)) = IDENTIFIERS.iter().find(|(_, name)| *name == identifier) else {
                return Err(ClipStoreError::corrupted());
            };
            if !applied.contains(known) {
                applied.push(*known);
            }
        }
    }
    Ok(applied)
}

fn create_tables(transaction: &Transaction, version: i64) -> Result<(), rusqlite::Error> {
    match version {
        1 => transaction.execute_batch(&format!(r#"CREATE TABLE "clips" {CLIPS_BODY}"#)),
        2 => transaction.execute_batch(&format!(r#"CREATE TABLE "clipSearchTerms" {TERMS_BODY}"#)),
        _ => rebuild_non_strict(transaction),
    }
}

fn is_strict(transaction: &Transaction, table: &str) -> Result<bool, rusqlite::Error> {
    transaction.query_row(
        "SELECT strict FROM pragma_table_list WHERE schema = 'main' AND name = ?1",
        [table],
        |row| row.get(0),
    )
}

/// 비 STRICT 표만 재구성하고 식별자를 소문자로 변환
/// iOS 표는 이미 STRICT라 쓰지 않음
fn rebuild_non_strict(transaction: &Transaction) -> Result<(), rusqlite::Error> {
    if !is_strict(transaction, "clips")? {
        transaction.execute_batch(&format!(
            r#"CREATE TABLE "clips_rebuilt" {CLIPS_BODY};
            INSERT INTO "clips_rebuilt" (id, kind, text, imageFileID, imageContentType, pixelWidth, pixelHeight, byteCount, name, pinnedAt, memo, createdAt, lastUsedAt)
            SELECT lower(id), kind, text, lower(imageFileID), imageContentType, pixelWidth, pixelHeight, byteCount, name, pinnedAt, memo, createdAt, lastUsedAt FROM clips;
            DROP TABLE clips;
            ALTER TABLE "clips_rebuilt" RENAME TO "clips";"#
        ))?;
    }
    if !is_strict(transaction, "clipSearchTerms")? {
        transaction.execute_batch(&format!(
            r#"CREATE TABLE "clipSearchTerms_rebuilt" {TERMS_BODY};
            INSERT INTO "clipSearchTerms_rebuilt" (position, term) SELECT position, term FROM clipSearchTerms;
            DROP TABLE clipSearchTerms;
            ALTER TABLE "clipSearchTerms_rebuilt" RENAME TO "clipSearchTerms";"#
        ))?;
    }
    Ok(())
}

/// 이전 빌드가 표를 다시 만들지 않도록 grdb_migrations 행을 함께 추가
fn record_identifier(transaction: &Transaction, version: i64) -> Result<(), rusqlite::Error> {
    if !has_grdb_table(transaction)? {
        return Ok(());
    }
    if let Some((_, identifier)) = IDENTIFIERS.iter().find(|(known, _)| *known == version) {
        transaction.execute(
            "INSERT OR IGNORE INTO grdb_migrations (identifier) VALUES (?1)",
            [identifier],
        )?;
    }
    Ok(())
}

/// 이미 최신이면 쓰지 않음
/// 두 프로세스가 동시에 처음 열어도 안전하도록 쓰기 잠금 안에서 다시 판단
pub(crate) fn migrate(connection: &mut Connection) -> Result<(), ClipStoreError> {
    if applied_versions(connection)?.len() as i64 == LATEST_VERSION {
        return Ok(());
    }
    let transaction = connection
        .transaction_with_behavior(TransactionBehavior::Immediate)
        .map_err(write_failed)?;
    let applied = applied_versions(&transaction)?;
    for version in 1..=LATEST_VERSION {
        if applied.contains(&version) {
            continue;
        }
        create_tables(&transaction, version).map_err(write_failed)?;
        record_identifier(&transaction, version).map_err(write_failed)?;
    }
    transaction
        .pragma_update(None, "user_version", LATEST_VERSION)
        .map_err(write_failed)?;
    transaction.commit().map_err(write_failed)
}
