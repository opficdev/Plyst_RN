mod support;

use plyst_core::store::{
    ClipSortOrderValue, ClipStore, ClipStoreError, ClipUpdateValue, ClipValue,
};
use support::{execute, identity, image, open, text, Directory, CORRUPTED};

const ID: &str = "11111111-AAAA-4BBB-8CCC-DDDDDDDDDDDD";
const LOWER_ID: &str = "11111111-aaaa-4bbb-8ccc-dddddddddddd";
const OTHER_ID: &str = "22222222-AAAA-4BBB-8CCC-DDDDDDDDDDDD";
const FILE_ID: &str = "33333333-AAAA-4BBB-8CCC-DDDDDDDDDDDD";

fn details(name: &str, is_pinned: bool, requested_at: f64) -> ClipUpdateValue {
    ClipUpdateValue::Details {
        name: Some(name.to_string()),
        memo: None,
        is_pinned,
        requested_at,
    }
}

fn single(path: &str) -> std::sync::Arc<ClipStore> {
    let store = open(path);
    store.insert(text(ID, "원문")).unwrap();
    store
}

#[test]
fn text_and_image_are_restored_by_another_store() {
    let directory = Directory::new();
    let path = directory.database();
    let clip = ClipValue {
        name: Some(String::new()),
        pinned_at: Some(793109290.0612345),
        memo: Some("메모\0끝".to_string()),
        last_used_at: Some(793109300.1234567),
        ..text(ID, "  한글 'text'\0🙂\nhttps://example.com  ")
    };
    let picture = image(OTHER_ID, FILE_ID);
    let store = open(&path);
    store.insert(clip.clone()).unwrap();
    store.insert(picture.clone()).unwrap();
    let restored = open(&path);
    assert_eq!(restored.fetch(ID.to_string()).unwrap(), Some(clip));
    assert_eq!(restored.fetch(OTHER_ID.to_string()).unwrap(), Some(picture));
}

#[test]
fn identifiers_are_stored_lowercase_and_returned_uppercase() {
    let directory = Directory::new();
    let path = directory.database();
    let store = open(&path);
    store.insert(image(ID, FILE_ID)).unwrap();
    let connection = rusqlite::Connection::open(&path).unwrap();
    let (id, file_id): (String, String) = connection
        .query_row("SELECT id, imageFileID FROM clips", [], |row| {
            Ok((row.get(0)?, row.get(1)?))
        })
        .unwrap();
    assert_eq!(id, LOWER_ID);
    assert_eq!(file_id, FILE_ID.to_ascii_lowercase());
    assert_eq!(
        store.fetch(LOWER_ID.to_string()).unwrap(),
        Some(image(ID, FILE_ID))
    );
    assert_eq!(
        store.fetch(ID.to_string()).unwrap(),
        Some(image(ID, FILE_ID))
    );
    assert_eq!(
        store.insert(text(LOWER_ID, "중복")),
        Err(ClipStoreError::DuplicateId {
            id: LOWER_ID.to_string()
        })
    );
    store.delete(ID.to_string()).unwrap();
    assert_eq!(store.fetch(LOWER_ID.to_string()).unwrap(), None);
}

#[test]
fn missing_clip_is_reported() {
    let directory = Directory::new();
    let store = open(&directory.database());
    let not_found = ClipStoreError::NotFound { id: ID.to_string() };
    assert_eq!(
        store
            .update(ID.to_string(), details("이름", false, 0.0))
            .err(),
        Some(not_found.clone())
    );
    assert_eq!(store.delete(ID.to_string()), Err(not_found));
}

#[test]
fn pin_keeps_the_first_time_and_unchanged_update_reports_no_change() {
    let directory = Directory::new();
    let store = single(&directory.database());
    let pinned = store
        .update(ID.to_string(), details("이름", true, 300.5))
        .unwrap();
    assert!(pinned.changed);
    assert_eq!(pinned.clip.pinned_at, Some(300.5));
    let same = store
        .update(ID.to_string(), details("이름", true, 900.5))
        .unwrap();
    assert!(!same.changed);
    assert_eq!(same.clip.pinned_at, Some(300.5));
    let cleared = store
        .update(ID.to_string(), details("이름", false, 900.5))
        .unwrap();
    assert_eq!(cleared.clip.pinned_at, None);
}

#[test]
fn usage_applies_only_to_the_matching_clip() {
    let directory = Directory::new();
    let store = open(&directory.database());
    let picture = image(ID, FILE_ID);
    store.insert(picture.clone()).unwrap();
    let mut stale = identity(&picture);
    stale.created_at = 1.5;
    let skipped = store
        .update(
            ID.to_string(),
            ClipUpdateValue::LastUsedAt {
                date: 700.5,
                matching: Some(stale),
            },
        )
        .unwrap();
    assert!(!skipped.changed);
    let other = identity(&image(ID, OTHER_ID));
    let skipped = store
        .update(
            ID.to_string(),
            ClipUpdateValue::LastUsedAt {
                date: 700.5,
                matching: Some(other),
            },
        )
        .unwrap();
    assert!(!skipped.changed);
    let applied = store
        .update(
            ID.to_string(),
            ClipUpdateValue::LastUsedAt {
                date: 700.5,
                matching: Some(identity(&picture)),
            },
        )
        .unwrap();
    assert!(applied.changed);
    assert_eq!(applied.clip.last_used_at, Some(700.5));
}

#[test]
fn usage_keeps_details_and_details_keep_usage() {
    let directory = Directory::new();
    let store = single(&directory.database());
    store
        .update(
            ID.to_string(),
            ClipUpdateValue::LastUsedAt {
                date: 700.5,
                matching: None,
            },
        )
        .unwrap();
    let updated = store
        .update(ID.to_string(), details("이름", false, 1.0))
        .unwrap()
        .clip;
    assert_eq!(updated.last_used_at, Some(700.5));
    assert_eq!(updated.content, text(ID, "원문").content);
    assert_eq!(updated.created_at, text(ID, "원문").created_at);
    let used = store
        .update(
            ID.to_string(),
            ClipUpdateValue::LastUsedAt {
                date: 800.5,
                matching: None,
            },
        )
        .unwrap()
        .clip;
    assert_eq!(used.name.as_deref(), Some("이름"));
}

#[test]
fn failed_update_rolls_back_and_the_next_write_succeeds() {
    let directory = Directory::new();
    let path = directory.database();
    let store = single(&path);
    execute(&path, "CREATE TRIGGER rejectUpdate AFTER UPDATE ON clips BEGIN SELECT RAISE(ABORT, 'Rejected update'); END");
    assert!(matches!(
        store.update(ID.to_string(), details("실패", false, 1.0)),
        Err(ClipStoreError::WriteFailed { .. })
    ));
    assert_eq!(store.fetch(ID.to_string()).unwrap(), Some(text(ID, "원문")));
    execute(&path, "DROP TRIGGER rejectUpdate");
    assert!(
        store
            .update(ID.to_string(), details("저장", false, 1.0))
            .unwrap()
            .changed
    );
}

#[test]
fn invalid_stored_values_are_reported_as_corrupted_data() {
    for sql in [
        "UPDATE clips SET text = '   '",
        "UPDATE clips SET pinnedAt = 1e999",
        "UPDATE clips SET id = 'not-a-uuid'",
        "PRAGMA ignore_check_constraints = ON; UPDATE clips SET kind = 'unknown'",
    ] {
        let directory = Directory::new();
        let path = directory.database();
        let store = single(&path);
        execute(&path, sql);
        assert_eq!(
            store.fetch_all(ClipSortOrderValue::CreatedAt),
            Err(CORRUPTED),
            "{sql}"
        );
    }
}

#[test]
fn stored_value_failure_is_reported_for_one_clip() {
    let directory = Directory::new();
    let path = directory.database();
    let store = single(&path);
    execute(&path, "UPDATE clips SET text = '   '");
    assert_eq!(store.fetch(ID.to_string()), Err(CORRUPTED));
}

#[test]
fn schema_rejects_invalid_shapes_and_types() {
    let directory = Directory::new();
    let path = directory.database();
    let store = open(&path);
    store.insert(text(ID, "원문")).unwrap();
    store.insert(image(OTHER_ID, FILE_ID)).unwrap();
    let connection = rusqlite::Connection::open(&path).unwrap();
    for sql in [
        "UPDATE clips SET kind = 'unknown' WHERE kind = 'text'",
        "UPDATE clips SET text = NULL WHERE kind = 'text'",
        "UPDATE clips SET imageFileID = 'file' WHERE kind = 'text'",
        "UPDATE clips SET createdAt = 'invalid'",
        "UPDATE clips SET pinnedAt = 'invalid'",
        "UPDATE clips SET text = 'text' WHERE kind = 'image'",
        "UPDATE clips SET imageFileID = NULL WHERE kind = 'image'",
        "UPDATE clips SET imageContentType = NULL WHERE kind = 'image'",
        "UPDATE clips SET pixelWidth = 0 WHERE kind = 'image'",
        "UPDATE clips SET pixelHeight = -1 WHERE kind = 'image'",
        "UPDATE clips SET byteCount = 0 WHERE kind = 'image'",
    ] {
        assert!(connection.execute_batch(sql).is_err(), "{sql}");
    }
    assert_eq!(store.fetch(ID.to_string()).unwrap(), Some(text(ID, "원문")));
    assert_eq!(
        store.fetch(OTHER_ID.to_string()).unwrap(),
        Some(image(OTHER_ID, FILE_ID))
    );
}

#[test]
fn non_finite_times_are_rejected_before_writing() {
    let directory = Directory::new();
    let store = open(&directory.database());
    for value in [f64::NAN, f64::INFINITY, f64::NEG_INFINITY] {
        let invalid = ClipValue {
            pinned_at: Some(value),
            ..text(ID, "원문")
        };
        assert_eq!(store.insert(invalid), Err(ClipStoreError::InvalidContent));
        let invalid = ClipValue {
            created_at: value,
            ..text(ID, "원문")
        };
        assert_eq!(store.insert(invalid), Err(ClipStoreError::InvalidContent));
    }
    assert!(store
        .fetch_all(ClipSortOrderValue::CreatedAt)
        .unwrap()
        .is_empty());
    store.insert(text(ID, "원문")).unwrap();
    let change = ClipUpdateValue::LastUsedAt {
        date: f64::NAN,
        matching: None,
    };
    assert_eq!(
        store.update(ID.to_string(), change).err(),
        Some(ClipStoreError::InvalidContent)
    );
}

#[test]
fn clips_are_ordered_newest_first_then_by_identifier() {
    let directory = Directory::new();
    let store = open(&directory.database());
    for (id, created_at) in [(OTHER_ID, 5.5), (ID, 5.5), (FILE_ID, 9.5)] {
        store
            .insert(ClipValue {
                created_at,
                ..text(id, "원문")
            })
            .unwrap();
    }
    let ids: Vec<String> = store
        .fetch_all(ClipSortOrderValue::CreatedAt)
        .unwrap()
        .into_iter()
        .map(|clip| clip.id)
        .collect();
    assert_eq!(ids, [FILE_ID, ID, OTHER_ID]);
}

#[test]
fn negative_zero_time_is_ordered_like_zero() {
    let directory = Directory::new();
    let store = open(&directory.database());
    store
        .insert(ClipValue {
            created_at: 0.0,
            ..text(OTHER_ID, "원문")
        })
        .unwrap();
    store
        .insert(ClipValue {
            created_at: -0.0,
            ..text(ID, "원문")
        })
        .unwrap();
    let ids: Vec<String> = store
        .fetch_all(ClipSortOrderValue::CreatedAt)
        .unwrap()
        .into_iter()
        .map(|clip| clip.id)
        .collect();
    assert_eq!(ids, [ID, OTHER_ID]);
}

#[test]
fn two_stores_writing_at_once_keep_every_clip() {
    let directory = Directory::new();
    let path = directory.database();
    drop(open(&path));
    let threads: Vec<_> = (0..4)
        .map(|writer| {
            let path = path.clone();
            std::thread::spawn(move || {
                let store = open(&path);
                for index in 0..25 {
                    store
                        .insert(text(
                            &format!("CCCCCCCC-0000-4000-8000-{writer:06X}{index:06X}"),
                            "동시",
                        ))
                        .unwrap();
                }
            })
        })
        .collect();
    for thread in threads {
        thread.join().unwrap();
    }
    assert_eq!(
        open(&path)
            .fetch_all(ClipSortOrderValue::CreatedAt)
            .unwrap()
            .len(),
        100
    );
}

#[test]
fn search_terms_are_restored_in_order_and_removal_recovers_corruption() {
    let directory = Directory::new();
    let path = directory.database();
    let store = open(&path);
    store.record_search_term("first".to_string()).unwrap();
    assert_eq!(
        store.record_search_term("second".to_string()).unwrap(),
        ["second", "first"]
    );
    assert_eq!(
        open(&path).fetch_search_terms().unwrap(),
        ["second", "first"]
    );
    assert_eq!(
        store.remove_search_term("없음".to_string()).unwrap(),
        ["second", "first"]
    );
    assert_eq!(
        store.remove_search_term("first".to_string()).unwrap(),
        ["second"]
    );
    execute(&path, "INSERT INTO clipSearchTerms VALUES (9, ' 공백 ')");
    assert_eq!(store.fetch_search_terms(), Err(CORRUPTED));
    assert_eq!(
        store.record_search_term("third".to_string()),
        Err(CORRUPTED)
    );
    store.remove_all_search_terms().unwrap();
    assert!(store.fetch_search_terms().unwrap().is_empty());
}
