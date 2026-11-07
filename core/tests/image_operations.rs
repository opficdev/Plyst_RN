mod support;

use std::fs;
use std::sync::{Arc, Barrier};
use std::thread;

use plyst_core::operations::{
    ClipCancellationSource, ClipCleanupValue, ClipCodecError, ClipImageDraftValue,
    ClipImageOperations, ClipImageSavedValue, ClipOperationError,
};
use plyst_core::store::{ClipChangeValue, ClipStoreError, ClipValue};
use support::{
    execute, file_id, image_value, make_read_only, make_writable, never_cancelled, png_properties,
    text, CancelFlag, CancelledAfter, Operations, FILE_DATA,
};

fn id(number: u8) -> String {
    format!("00000000-0000-4000-8000-0000000000{number:02X}")
}

fn draft(number: u8) -> ClipImageDraftValue {
    ClipImageDraftValue {
        id: id(number),
        name: Some("이름".to_string()),
        memo: Some("메모".to_string()),
        pinned_at: Some(1.0),
        created_at: 100.0,
    }
}

fn save(images: &ClipImageOperations, number: u8) -> ClipValue {
    images
        .save_image(
            FILE_DATA,
            png_properties(),
            draft(number),
            never_cancelled(),
        )
        .unwrap()
        .clip
}

fn saved_with(
    images: &ClipImageOperations,
    number: u8,
    cancellation: Arc<dyn ClipCancellationSource>,
) -> Result<ClipImageSavedValue, ClipOperationError> {
    images.save_image(FILE_DATA, png_properties(), draft(number), cancellation)
}

fn pending(fixture: &Operations) -> Vec<String> {
    fixture
        .images
        .recover_pending_cleanup(never_cancelled())
        .unwrap()
}

#[test]
fn saved_clip_and_original_are_restored_by_new_instances() {
    let fixture = Operations::new();
    let saved = saved_with(&fixture.images, 1, never_cancelled()).unwrap();
    assert_eq!(saved.cleanup, ClipCleanupValue::Completed);
    assert_eq!(saved.clip.name.as_deref(), Some("이름"));
    assert_eq!(
        fixture.changes.taken(),
        vec![ClipChangeValue::Inserted {
            clip: saved.clip.clone()
        }]
    );
    let reopened = fixture.reopened();
    let path = reopened
        .load_image(image_value(&saved.clip), never_cancelled())
        .unwrap();
    assert_eq!(fs::read(path).unwrap(), FILE_DATA);
    assert_eq!(fixture.store.fetch(id(1)).unwrap(), Some(saved.clip));
}

#[test]
fn duplicate_insert_cleans_only_new_original_and_does_not_report() {
    let fixture = Operations::new();
    let first = save(&fixture.images, 1);
    fixture.changes.taken();
    let duplicate = saved_with(&fixture.images, 1, never_cancelled());
    assert_eq!(
        duplicate.unwrap_err(),
        ClipOperationError::Storage {
            error: ClipStoreError::DuplicateId { id: id(1) }
        }
    );
    assert_eq!(fixture.folders(), vec![file_id(&first)]);
    assert!(fixture.changes.taken().is_empty());
}

#[test]
fn cancelled_before_save_leaves_no_file() {
    let fixture = Operations::new();
    let saved = saved_with(&fixture.images, 1, CancelledAfter::reads(0));
    assert_eq!(saved.unwrap_err(), ClipOperationError::Cancelled);
    assert!(fixture.folders().is_empty());
}

#[test]
fn cancelled_before_insert_removes_saved_file_at_once() {
    let fixture = Operations::new();
    let saved = saved_with(&fixture.images, 1, CancelledAfter::reads(1));
    assert_eq!(saved.unwrap_err(), ClipOperationError::Cancelled);
    assert!(fixture.folders().is_empty());
    assert_eq!(fixture.store.fetch(id(1)).unwrap(), None);
    assert!(fixture.changes.taken().is_empty());
}

#[test]
fn cancelled_after_insert_commit_reports_saved_clip() {
    let fixture = Operations::new();
    let flag = Arc::new(CancelFlag::default());
    let cancel = flag.clone();
    fixture.changes.on_next_change(move |_| cancel.cancel());
    let saved = saved_with(&fixture.images, 1, flag).unwrap();
    assert_eq!(saved.cleanup, ClipCleanupValue::Completed);
    assert!(fixture.store.fetch(id(1)).unwrap().is_some());
    assert_eq!(pending(&fixture), Vec::<String>::new());
}

#[test]
fn failed_marker_removal_reports_committed_save_and_recovery_preserves_reference() {
    let fixture = Operations::new();
    let root = fixture.directory.0.join("images");
    fixture.changes.on_next_change(move |change| {
        let ClipChangeValue::Inserted { clip } = change else {
            panic!("추가 변경이 아님")
        };
        make_read_only(&root.join(file_id(clip)));
    });
    let saved = saved_with(&fixture.images, 1, never_cancelled()).unwrap();
    let file = file_id(&saved.clip);
    assert_eq!(
        saved.cleanup,
        ClipCleanupValue::Pending {
            file_id: file.clone()
        }
    );
    make_writable(&fixture.folder(&file));
    let reopened = fixture.reopened();
    assert_eq!(
        reopened.recover_pending_cleanup(never_cancelled()).unwrap(),
        Vec::<String>::new()
    );
    let path = reopened
        .load_image(image_value(&saved.clip), never_cancelled())
        .unwrap();
    assert_eq!(fs::read(path).unwrap(), FILE_DATA);
}

#[test]
fn rejected_deletion_preserves_clip_original_and_events() {
    let fixture = Operations::new();
    let clip = save(&fixture.images, 1);
    fixture.changes.taken();
    execute(
        &fixture.directory.database(),
        "CREATE TRIGGER reject BEFORE DELETE ON clips BEGIN SELECT RAISE(ABORT, 'x'); END;",
    );
    let deleted = fixture.images.delete_clip(id(1), never_cancelled());
    assert!(matches!(
        deleted,
        Err(ClipOperationError::Storage {
            error: ClipStoreError::WriteFailed { .. }
        })
    ));
    assert_eq!(fixture.store.fetch(id(1)).unwrap(), Some(clip.clone()));
    let path = fixture
        .images
        .load_image(image_value(&clip), never_cancelled())
        .unwrap();
    assert_eq!(fs::read(path).unwrap(), FILE_DATA);
    assert!(fixture.changes.taken().is_empty());
}

#[test]
fn cancelled_after_marker_keeps_clip_and_recovery_releases_marker() {
    let fixture = Operations::new();
    let clip = save(&fixture.images, 1);
    let deleted = fixture.images.delete_clip(id(1), CancelledAfter::reads(1));
    assert_eq!(deleted.unwrap_err(), ClipOperationError::Cancelled);
    assert_eq!(fixture.store.fetch(id(1)).unwrap(), Some(clip.clone()));
    assert_eq!(pending(&fixture), Vec::<String>::new());
    let path = fixture
        .images
        .load_image(image_value(&clip), never_cancelled())
        .unwrap();
    assert_eq!(fs::read(path).unwrap(), FILE_DATA);
    assert!(!fixture.folder(&file_id(&clip)).join("pending").exists());
}

#[test]
fn cancelled_after_delete_commit_reports_deleted_with_pending_cleanup() {
    let fixture = Operations::new();
    let clip = save(&fixture.images, 1);
    let flag = Arc::new(CancelFlag::default());
    let cancel = flag.clone();
    fixture.changes.on_next_change(move |_| cancel.cancel());
    let cleanup = fixture.images.delete_clip(id(1), flag).unwrap();
    let file = file_id(&clip);
    assert_eq!(
        cleanup,
        ClipCleanupValue::Pending {
            file_id: file.clone()
        }
    );
    assert_eq!(fixture.store.fetch(id(1)).unwrap(), None);
    assert_eq!(pending(&fixture), Vec::<String>::new());
    assert!(!fixture.folder(&file).exists());
}

#[test]
fn committed_deletion_with_failed_cleanup_is_recovered_after_reopening() {
    let fixture = Operations::new();
    let clip = save(&fixture.images, 1);
    let file = file_id(&clip);
    let folder = fixture.folder(&file);
    let locked = folder.clone();
    fixture.changes.taken();
    fixture
        .changes
        .on_next_change(move |_| make_read_only(&locked));
    let cleanup = fixture
        .images
        .delete_clip(id(1), never_cancelled())
        .unwrap();
    assert_eq!(
        cleanup,
        ClipCleanupValue::Pending {
            file_id: file.clone()
        }
    );
    assert_eq!(fixture.store.fetch(id(1)).unwrap(), None);
    assert_eq!(
        fixture.changes.taken(),
        vec![ClipChangeValue::Deleted { id: id(1) }]
    );
    assert_eq!(pending(&fixture), vec![file]);
    make_writable(&folder);
    let reopened = fixture.reopened();
    assert_eq!(
        reopened.recover_pending_cleanup(never_cancelled()).unwrap(),
        Vec::<String>::new()
    );
    assert!(fixture.folders().is_empty());
}

#[test]
fn failed_reference_query_keeps_candidate_and_original_until_retry() {
    let fixture = Operations::new();
    let clip = save(&fixture.images, 1);
    let file = file_id(&clip);
    let database = fixture.directory.database();
    let renamed = database.clone();
    fixture.changes.taken();
    fixture
        .changes
        .on_next_change(move |_| execute(&renamed, "ALTER TABLE clips RENAME TO hidden"));
    let cleanup = fixture
        .images
        .delete_clip(id(1), never_cancelled())
        .unwrap();
    assert_eq!(
        cleanup,
        ClipCleanupValue::Pending {
            file_id: file.clone()
        }
    );
    let recovered = fixture.images.recover_pending_cleanup(never_cancelled());
    assert!(matches!(
        recovered,
        Err(ClipOperationError::Storage {
            error: ClipStoreError::ReadFailed { .. }
        })
    ));
    assert_eq!(
        fs::read(fixture.folder(&file).join("original")).unwrap(),
        FILE_DATA
    );
    execute(&database, "ALTER TABLE hidden RENAME TO clips");
    assert_eq!(pending(&fixture), Vec::<String>::new());
    assert!(!fixture.folder(&file).exists());
}

#[test]
fn shared_original_is_removed_only_after_last_reference() {
    let fixture = Operations::new();
    let first = save(&fixture.images, 1);
    let second = ClipValue {
        id: id(2),
        ..first.clone()
    };
    fixture.store.insert(second.clone()).unwrap();
    let cleanup = fixture
        .images
        .delete_clip(id(1), never_cancelled())
        .unwrap();
    assert_eq!(cleanup, ClipCleanupValue::Completed);
    let path = fixture
        .images
        .load_image(image_value(&second), never_cancelled())
        .unwrap();
    assert_eq!(fs::read(path).unwrap(), FILE_DATA);
    let cleanup = fixture
        .images
        .delete_clip(id(2), never_cancelled())
        .unwrap();
    assert_eq!(cleanup, ClipCleanupValue::Completed);
    assert!(fixture.folders().is_empty());
}

#[test]
fn text_clip_deletion_touches_no_file() {
    let fixture = Operations::new();
    let clip = text(&id(1), "메모");
    fixture.store.insert(clip.clone()).unwrap();
    let cleanup = fixture
        .images
        .delete_clip(clip.id, never_cancelled())
        .unwrap();
    assert_eq!(cleanup, ClipCleanupValue::Completed);
}

#[test]
fn recovery_handles_interrupted_directories_without_deleting_completed_file() {
    let fixture = Operations::new();
    let kept = save(&fixture.images, 1);
    let orphan = save(&fixture.images, 2);
    fixture.store.delete(id(2)).unwrap();
    fs::write(fixture.folder(&file_id(&orphan)).join("pending"), []).unwrap();
    let empty = fixture.folder("00000000-0000-4000-8000-0000000000FF");
    fs::create_dir(&empty).unwrap();
    fs::write(empty.join("temporary"), b"partial").unwrap();
    assert_eq!(pending(&fixture), Vec::<String>::new());
    assert_eq!(fixture.folders(), vec![file_id(&kept)]);
}

#[test]
fn recovery_finishes_deletion_interrupted_before_or_after_marker_removal() {
    for remove_marker in [false, true] {
        let fixture = Operations::new();
        let clip = save(&fixture.images, 1);
        let folder = fixture.folder(&file_id(&clip));
        fs::write(folder.join("pending"), []).unwrap();
        fixture.store.delete(id(1)).unwrap();
        fs::remove_file(folder.join("original")).unwrap();
        if remove_marker {
            fs::remove_file(folder.join("pending")).unwrap();
        }
        let reopened = fixture.reopened();
        assert_eq!(
            reopened.recover_pending_cleanup(never_cancelled()).unwrap(),
            Vec::<String>::new()
        );
        assert!(!folder.exists());
    }
}

#[test]
fn missing_original_does_not_delete_metadata() {
    let fixture = Operations::new();
    let clip = save(&fixture.images, 1);
    let file = file_id(&clip);
    fs::remove_dir_all(fixture.folder(&file)).unwrap();
    let loaded = fixture
        .images
        .load_image(image_value(&clip), never_cancelled());
    assert!(matches!(loaded, Err(ClipOperationError::Files { .. })));
    assert_eq!(fixture.store.fetch(id(1)).unwrap(), Some(clip));
    let cleanup = fixture
        .images
        .delete_clip(id(1), never_cancelled())
        .unwrap();
    assert_eq!(cleanup, ClipCleanupValue::Completed);
}

#[test]
fn changed_original_reports_corruption() {
    let fixture = Operations::new();
    let clip = save(&fixture.images, 1);
    let file = file_id(&clip);
    fs::write(fixture.folder(&file).join("original"), b"short").unwrap();
    let loaded = fixture
        .images
        .load_image(image_value(&clip), never_cancelled());
    assert_eq!(
        loaded.unwrap_err(),
        ClipOperationError::CorruptedImage {
            file_id: file.clone()
        }
    );
    fs::write(fixture.folder(&file).join("original"), FILE_DATA).unwrap();
    *fixture.codec.properties.lock().unwrap() = Err(ClipCodecError::Corrupted);
    let loaded = fixture
        .images
        .load_image(image_value(&clip), never_cancelled());
    assert_eq!(
        loaded.unwrap_err(),
        ClipOperationError::CorruptedImage { file_id: file }
    );
}

#[test]
fn derived_files_are_written_beside_the_original() {
    let fixture = Operations::new();
    let clip = save(&fixture.images, 1);
    let folder = fixture.folder(&file_id(&clip));
    let preview = fixture
        .images
        .make_preview(image_value(&clip), never_cancelled())
        .unwrap();
    assert_eq!(fs::read(preview).unwrap(), b"derived");
    let thumbnail = fixture
        .images
        .make_thumbnail(image_value(&clip), 300, never_cancelled())
        .unwrap();
    assert_eq!(fs::read(thumbnail).unwrap(), b"derived");
    assert!(folder.join("thumbnail-300").exists());
    let refused = fixture
        .images
        .make_thumbnail(image_value(&clip), 0, never_cancelled());
    assert!(matches!(refused, Err(ClipOperationError::Files { .. })));
    let cancelled =
        fixture
            .images
            .make_thumbnail(image_value(&clip), 400, CancelledAfter::reads(1));
    assert_eq!(cancelled.unwrap_err(), ClipOperationError::Cancelled);
    assert!(!folder.join("thumbnail-400").exists());
}

#[test]
fn concurrent_saves_and_recovery_preserve_every_committed_original() {
    let fixture = Operations::new();
    let barrier = Arc::new(Barrier::new(24));
    let workers: Vec<_> = (0..12u8)
        .flat_map(|number| {
            let saver = (fixture.images.clone(), barrier.clone());
            let recoverer = (fixture.images.clone(), barrier.clone());
            [
                thread::spawn(move || {
                    saver.1.wait();
                    Some(save(&saver.0, number + 1))
                }),
                thread::spawn(move || {
                    recoverer.1.wait();
                    recoverer
                        .0
                        .recover_pending_cleanup(never_cancelled())
                        .unwrap();
                    None
                }),
            ]
        })
        .collect();
    let clips: Vec<ClipValue> = workers
        .into_iter()
        .filter_map(|worker| worker.join().unwrap())
        .collect();
    assert_eq!(clips.len(), 12);
    for clip in &clips {
        assert_eq!(
            fs::read(fixture.folder(&file_id(clip)).join("original")).unwrap(),
            FILE_DATA
        );
    }
    assert_eq!(pending(&fixture), Vec::<String>::new());
    assert_eq!(fixture.folders().len(), 12);
}
