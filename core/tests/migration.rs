mod support;

use std::fs;

use plyst_core::store::{ClipContentValue, ClipSortOrderValue, ClipStore, ClipStoreError};
use rusqlite::Connection;
use support::{execute, ignored_changes, open, text, Directory, CORRUPTED};

const FIRST: &str = "11111111-AAAA-4BBB-8CCC-DDDDDDDDDDDD";
const SECOND: &str = "22222222-AAAA-4BBB-8CCC-DDDDDDDDDDDD";
const THIRD: &str = "44444444-AAAA-4BBB-8CCC-DDDDDDDDDDDD";

fn schema(path: &str) -> Vec<String> {
    let connection = Connection::open(path).unwrap();
    let mut statement = connection
        .prepare("SELECT sql FROM sqlite_master WHERE type = 'table' ORDER BY name")
        .unwrap();
    let rows: Vec<String> = statement
        .query_map([], |row| row.get(0))
        .unwrap()
        .map(Result::unwrap)
        .collect();
    rows
}

fn identifiers(path: &str) -> Vec<String> {
    let connection = Connection::open(path).unwrap();
    let mut statement = connection
        .prepare("SELECT identifier FROM grdb_migrations ORDER BY rowid")
        .unwrap();
    let rows: Vec<String> = statement
        .query_map([], |row| row.get(0))
        .unwrap()
        .map(Result::unwrap)
        .collect();
    rows
}

fn user_version(path: &str) -> i64 {
    Connection::open(path)
        .unwrap()
        .pragma_query_value(None, "user_version", |row| row.get(0))
        .unwrap()
}

fn assert_rejected_without_change(path: &str, expected: ClipStoreError) {
    let before = fs::read(path).unwrap();
    assert_eq!(
        ClipStore::open(path.to_string(), ignored_changes()).err(),
        Some(expected)
    );
    assert_eq!(fs::read(path).unwrap(), before);
}

#[test]
fn commits_that_only_exist_in_the_wal_are_read_with_every_field() {
    let directory = Directory::new();
    let path = directory.copy_fixture("grdb-wal");
    assert!(
        4096 < fs::metadata(directory.0.join("clips.sqlite-wal"))
            .unwrap()
            .len()
    );
    let store = open(&path);
    let clips = store.fetch_all(ClipSortOrderValue::CreatedAt).unwrap();
    assert_eq!(
        clips
            .iter()
            .map(|clip| clip.id.as_str())
            .collect::<Vec<_>>(),
        [SECOND, THIRD, FIRST]
    );
    let first = &clips[2];
    assert_eq!(
        first.content,
        ClipContentValue::Text {
            text: "  한글 'text'\0🙂\nhttps://example.com  ".to_string()
        }
    );
    assert_eq!(first.name.as_deref(), Some(""));
    assert_eq!(first.memo.as_deref(), Some("메모\0끝"));
    assert_eq!(first.created_at, 793109282.0612345);
    assert_eq!(first.pinned_at, Some(793109290.0612345));
    assert_eq!(first.last_used_at, Some(793109300.1234567));
    assert_eq!(
        clips[0].content,
        ClipContentValue::Image {
            file_id: "33333333-AAAA-4BBB-8CCC-DDDDDDDDDDDD".to_string(),
            content_type: "public.png".to_string(),
            pixel_width: 640,
            pixel_height: 480,
            byte_count: 4096,
        }
    );
    assert_eq!(store.fetch_search_terms().unwrap(), ["둘째 Term", "first"]);
}

#[test]
fn opening_and_writing_keeps_the_ios_schema_identifiers_and_lowercase_ids() {
    let directory = Directory::new();
    let path = directory.copy_fixture("grdb-wal");
    let before = schema(&path);
    let store = open(&path);
    store
        .insert(text("AAAAAAAA-0000-4000-8000-000000000001", "새 클립"))
        .unwrap();
    drop(store);
    assert_eq!(schema(&path), before);
    assert_eq!(identifiers(&path), ["CreateClips", "CreateClipSearchTerms"]);
    assert_eq!(user_version(&path), 3);
    let connection = Connection::open(&path).unwrap();
    let id: String = connection
        .query_row("SELECT id FROM clips WHERE text = '새 클립'", [], |row| {
            row.get(0)
        })
        .unwrap();
    assert_eq!(id, "aaaaaaaa-0000-4000-8000-000000000001");
}

#[test]
fn version_one_database_gains_search_terms_and_its_identifier_and_keeps_clips() {
    let directory = Directory::new();
    let path = directory.copy_fixture("grdb-v1");
    let store = open(&path);
    assert_eq!(
        store
            .fetch_all(ClipSortOrderValue::CreatedAt)
            .unwrap()
            .len(),
        3
    );
    assert!(store.fetch_search_terms().unwrap().is_empty());
    assert_eq!(
        store.record_search_term("alpha".to_string()).unwrap(),
        ["alpha"]
    );
    drop(store);
    assert_eq!(identifiers(&path), ["CreateClips", "CreateClipSearchTerms"]);
    assert_eq!(open(&path).fetch_search_terms().unwrap(), ["alpha"]);
}

#[test]
fn unknown_migration_is_rejected_without_changing_the_file() {
    let directory = Directory::new();
    let path = directory.copy_fixture("grdb-v1");
    execute(
        &path,
        "INSERT INTO grdb_migrations VALUES ('FutureMigration'); PRAGMA wal_checkpoint(TRUNCATE);",
    );
    assert_rejected_without_change(&path, CORRUPTED);
}

#[test]
fn future_version_is_rejected_without_changing_the_file() {
    let directory = Directory::new();
    let path = directory.database();
    drop(open(&path));
    execute(
        &path,
        "PRAGMA user_version = 4; PRAGMA wal_checkpoint(TRUNCATE);",
    );
    assert_rejected_without_change(&path, CORRUPTED);
}

#[test]
fn corrupted_file_is_reported_without_replacing_its_contents() {
    let directory = Directory::new();
    let path = directory.database();
    fs::write(&path, "Invalid SQLite data").unwrap();
    assert!(matches!(
        ClipStore::open(path.clone(), ignored_changes()),
        Err(ClipStoreError::CorruptedData { .. })
    ));
    assert_eq!(fs::read(&path).unwrap(), b"Invalid SQLite data");
}

const ANDROID_SCHEMA: &str = "
    CREATE TABLE android_metadata (locale TEXT);
    INSERT INTO android_metadata VALUES ('ko_KR');
    CREATE TABLE clips (
      id TEXT PRIMARY KEY NOT NULL, kind TEXT NOT NULL CHECK (kind = 'text' OR kind = 'image'),
      text TEXT, imageFileID TEXT, imageContentType TEXT, pixelWidth INTEGER, pixelHeight INTEGER, byteCount INTEGER,
      name TEXT, pinnedAt REAL, memo TEXT, createdAt REAL NOT NULL, lastUsedAt REAL);
    CREATE TABLE clipSearchTerms (position INTEGER PRIMARY KEY NOT NULL CHECK (0 <= position), term TEXT NOT NULL UNIQUE CHECK (term != ''));
    INSERT INTO clipSearchTerms VALUES (0, '첫째'), (1, '둘째');
    PRAGMA user_version = 2;";

#[test]
fn android_database_is_rebuilt_as_strict_with_lowercase_ids() {
    let directory = Directory::new();
    let path = directory.database();
    execute(&path, ANDROID_SCHEMA);
    execute(
        &path,
        "INSERT INTO clips (id, kind, text, createdAt) VALUES ('AAAAAAAA-1111-4111-8111-111111111111', 'text', '안드로이드', 100.5);
        INSERT INTO clips (id, kind, imageFileID, imageContentType, pixelWidth, pixelHeight, byteCount, createdAt)
        VALUES ('BBBBBBBB-1111-4111-8111-111111111111', 'image', 'CCCCCCCC-1111-4111-8111-111111111111', 'public.png', 1, 2, 3, 101.5);",
    );
    let store = open(&path);
    let clips = store.fetch_all(ClipSortOrderValue::CreatedAt).unwrap();
    assert_eq!(clips[0].id, "BBBBBBBB-1111-4111-8111-111111111111");
    assert_eq!(clips[1].id, "AAAAAAAA-1111-4111-8111-111111111111");
    assert_eq!(store.fetch_search_terms().unwrap(), ["첫째", "둘째"]);
    drop(store);
    let connection = Connection::open(&path).unwrap();
    let lowercase: i64 = connection
        .query_row(
            "SELECT count(*) FROM clips WHERE id = lower(id) AND imageFileID IS lower(imageFileID)",
            [],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(lowercase, 2);
    let strict: i64 = connection
        .query_row(
            "SELECT sum(strict) FROM pragma_table_list WHERE name IN ('clips', 'clipSearchTerms')",
            [],
            |row| row.get(0),
        )
        .unwrap();
    let locale: String = connection
        .query_row("SELECT locale FROM android_metadata", [], |row| row.get(0))
        .unwrap();
    assert_eq!(strict, 2);
    assert_eq!(locale, "ko_KR");
    assert_eq!(user_version(&path), 3);
}

#[test]
fn failed_android_rebuild_keeps_the_original_tables() {
    let directory = Directory::new();
    let path = directory.database();
    execute(&path, ANDROID_SCHEMA);
    execute(
        &path,
        "INSERT INTO clips (id, kind, text, createdAt) VALUES ('AAAAAAAA-1111-4111-8111-111111111111', 'text', '원본', 100.5);
        INSERT INTO clips (id, kind, text, createdAt) VALUES ('BBBBBBBB-1111-4111-8111-111111111111', 'text', '타입 오류', '문자열');",
    );
    assert!(matches!(
        ClipStore::open(path.clone(), ignored_changes()),
        Err(ClipStoreError::WriteFailed { .. })
    ));
    let connection = Connection::open(&path).unwrap();
    let (strict, count): (i64, i64) = connection
        .query_row("SELECT (SELECT strict FROM pragma_table_list WHERE name = 'clips'), count(*) FROM clips", [], |row| Ok((row.get(0)?, row.get(1)?)))
        .unwrap();
    assert_eq!((strict, count), (0, 2));
    assert_eq!(user_version(&path), 2);
}

#[test]
fn simultaneous_first_opens_all_succeed() {
    let directory = Directory::new();
    let path = directory.database();
    let threads: Vec<_> = (0..8)
        .map(|_| {
            let path = path.clone();
            std::thread::spawn(move || ClipStore::open(path, ignored_changes()).map(|_| ()))
        })
        .collect();
    for thread in threads {
        assert_eq!(thread.join().unwrap(), Ok(()));
    }
    assert_eq!(user_version(&path), 3);
}
