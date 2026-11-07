mod support;

use std::fs;
use std::os::unix::fs::{symlink, MetadataExt, PermissionsExt};
use std::path::{Path, PathBuf};
use std::sync::Arc;

use plyst_core::image_files::{ClipImageFiles, ClipImageFilesError};
use support::Directory;

const ID: &str = "11111111-AAAA-4BBB-8CCC-DDDDDDDDDDDD";
const OTHER_ID: &str = "22222222-AAAA-4BBB-8CCC-DDDDDDDDDDDD";
const LOWER_ID: &str = "11111111-aaaa-4bbb-8ccc-dddddddddddd";
const COMPLETE_ID: &str = "433D4888-53EF-4D86-A4BD-9F5BC14D4F5B";
const PENDING_ID: &str = "C5ECD0CD-9071-43F2-9EB2-49FEEC6FB897";
const BYTES: &[u8] = b"\x89PNG original bytes\0\xff";

fn root(directory: &Directory) -> PathBuf {
    directory.0.join("images")
}

fn open(directory: &Directory) -> Arc<ClipImageFiles> {
    ClipImageFiles::open(root(directory).to_str().unwrap().to_string()).unwrap()
}

fn tree(directory: &Directory, id: &str) -> PathBuf {
    root(directory).join(id)
}

fn names(path: &Path) -> Vec<String> {
    let mut names: Vec<String> = fs::read_dir(path)
        .unwrap()
        .map(|entry| entry.unwrap().file_name().to_str().unwrap().to_string())
        .collect();
    names.sort();
    names
}

fn copy_tree(source: &Path, target: &Path) {
    fs::create_dir_all(target).unwrap();
    for entry in fs::read_dir(source).unwrap() {
        let entry = entry.unwrap();
        let destination = target.join(entry.file_name());
        if entry.file_type().unwrap().is_dir() {
            copy_tree(&entry.path(), &destination);
        } else {
            fs::copy(entry.path(), destination).unwrap();
        }
    }
}

fn fixture(directory: &Directory) -> Arc<ClipImageFiles> {
    let source = Path::new(env!("CARGO_MANIFEST_DIR")).join("tests/fixtures/image-tree");
    copy_tree(&source, &root(directory));
    open(directory)
}

fn saved(directory: &Directory) -> (Arc<ClipImageFiles>, String) {
    let files = open(directory);
    let id = files.save(BYTES).unwrap();
    (files, id)
}

fn make_read_only(path: &Path) -> bool {
    fs::set_permissions(path, fs::Permissions::from_mode(0o500)).unwrap();
    // root 권한으로 실행하면 제한이 적용되지 않음
    fs::write(path.join(".probe"), b"").is_err()
}

fn make_writable(path: &Path) {
    fs::set_permissions(path, fs::Permissions::from_mode(0o700)).unwrap();
}

#[test]
fn saved_bytes_survive_reopening_and_stay_pending_until_released() {
    let directory = Directory::new();
    let (files, id) = saved(&directory);
    assert_eq!(names(&tree(&directory, &id)), ["original", "pending"]);
    assert_eq!(files.pending_file_ids().unwrap(), [id.as_str()]);

    let reopened = open(&directory);
    let path = reopened
        .validated_original_path(&id, BYTES.len() as i64)
        .unwrap();
    assert_eq!(fs::read(path).unwrap(), BYTES);
    reopened.finish_pending(&id).unwrap();
    reopened.finish_pending(&id).unwrap();
    assert!(reopened.pending_file_ids().unwrap().is_empty());
    assert_eq!(names(&tree(&directory, &id)), ["original"]);
}

#[test]
fn tree_written_by_the_swift_store_is_read_recovered_and_deleted() {
    let directory = Directory::new();
    let files = fixture(&directory);
    assert_eq!(files.pending_file_ids().unwrap(), [PENDING_ID]);
    let original = tree(&directory, COMPLETE_ID).join("original");
    let size = fs::metadata(&original).unwrap().len() as i64;
    assert_eq!(
        files.validated_original_path(COMPLETE_ID, size).unwrap(),
        original.to_str().unwrap()
    );

    files.delete(PENDING_ID).unwrap();
    files.delete(COMPLETE_ID).unwrap();
    assert!(names(&root(&directory)).is_empty());
}

#[test]
fn each_save_gets_its_own_identifier_in_the_disk_form() {
    let directory = Directory::new();
    let (files, first) = saved(&directory);
    let second = files.save(BYTES).unwrap();
    assert_ne!(first, second);
    let mut expected = vec![first, second];
    expected.sort();
    assert_eq!(files.pending_file_ids().unwrap(), expected);
}

#[test]
fn a_failed_write_leaves_no_folder() {
    let directory = Directory::new();
    let files = open(&directory);
    if !make_read_only(&root(&directory)) {
        make_writable(&root(&directory));
        return;
    }
    let result = files.save(BYTES);
    make_writable(&root(&directory));
    assert_eq!(result, Err(ClipImageFilesError::WriteFailed));
    assert!(names(&root(&directory)).is_empty());
}

#[test]
fn delete_removes_the_whole_tree_and_repeats_as_success() {
    let directory = Directory::new();
    let (files, id) = saved(&directory);
    files.write_preview(&id, b"preview").unwrap();
    files.write_thumbnail(&id, 240, b"thumbnail").unwrap();
    fs::write(tree(&directory, &id).join(".dat.nosync1234.abcd"), b"tmp").unwrap();
    fs::write(tree(&directory, &id).join(".original.1-1"), b"tmp").unwrap();
    fs::create_dir(tree(&directory, &id).join("unknown")).unwrap();
    fs::write(tree(&directory, &id).join("unknown/file"), b"x").unwrap();

    files.delete(&id).unwrap();
    files.delete(&id).unwrap();
    assert!(names(&root(&directory)).is_empty());
    assert!(files.pending_file_ids().unwrap().is_empty());
}

#[test]
fn delete_keeps_the_marker_until_every_other_entry_is_gone() {
    let directory = Directory::new();
    let (files, id) = saved(&directory);
    let blocked = tree(&directory, &id).join("blocked");
    fs::create_dir(&blocked).unwrap();
    fs::write(blocked.join("file"), b"x").unwrap();
    if !make_read_only(&blocked) {
        make_writable(&blocked);
        return;
    }

    let result = files.delete(&id);
    make_writable(&blocked);
    assert_eq!(result, Err(ClipImageFilesError::DeleteFailed));
    let left = names(&tree(&directory, &id));
    assert!(!left.contains(&"original".to_string()));
    assert!(left.contains(&"pending".to_string()));
    assert_eq!(files.pending_file_ids().unwrap(), [id.as_str()]);

    files.delete(&id).unwrap();
    assert!(names(&root(&directory)).is_empty());
}

#[test]
fn delete_of_a_link_removes_the_link_and_keeps_its_target() {
    let directory = Directory::new();
    let (files, id) = saved(&directory);
    let outside = directory.0.join("outside");
    fs::create_dir(&outside).unwrap();
    fs::write(outside.join("kept"), b"kept").unwrap();
    symlink(&outside, tree(&directory, &id).join("link")).unwrap();

    files.delete(&id).unwrap();
    assert!(names(&root(&directory)).is_empty());
    assert_eq!(names(&outside), ["kept"]);
}

#[test]
fn recovery_finds_interrupted_folders_and_leaves_intact_ones() {
    let directory = Directory::new();
    let files = open(&directory);
    let names_by_state = [
        ("11111111-0000-4000-8000-000000000000", &["pending"][..]),
        (
            "22222222-0000-4000-8000-000000000000",
            &["original", "pending"][..],
        ),
        ("33333333-0000-4000-8000-000000000000", &[][..]),
        ("44444444-0000-4000-8000-000000000000", &["original"][..]),
    ];
    for (id, entries) in names_by_state {
        fs::create_dir(tree(&directory, id)).unwrap();
        for name in entries {
            fs::write(tree(&directory, id).join(name), b"").unwrap();
        }
    }
    fs::create_dir(root(&directory).join(LOWER_ID)).unwrap();
    fs::create_dir(root(&directory).join("not-an-id")).unwrap();
    fs::write(root(&directory).join(".DS_Store"), b"").unwrap();

    assert_eq!(
        files.pending_file_ids().unwrap(),
        [
            "11111111-0000-4000-8000-000000000000",
            "22222222-0000-4000-8000-000000000000",
            "33333333-0000-4000-8000-000000000000",
        ]
    );
}

#[test]
fn links_are_refused_at_every_level_including_broken_ones() {
    let directory = Directory::new();
    let outside = directory.0.join("outside");
    fs::create_dir(&outside).unwrap();
    fs::write(outside.join("file"), b"secret").unwrap();
    let missing = directory.0.join("missing");

    let (files, id) = saved(&directory);
    for target in [outside.join("file"), missing.clone()] {
        fs::remove_file(tree(&directory, &id).join("original")).unwrap();
        symlink(&target, tree(&directory, &id).join("original")).unwrap();
        assert_eq!(
            files.validated_original_path(&id, 6),
            Err(ClipImageFilesError::UnsafePath)
        );
    }

    fs::remove_file(tree(&directory, &id).join("pending")).unwrap();
    symlink(outside.join("file"), tree(&directory, &id).join("pending")).unwrap();
    assert_eq!(
        files.mark_pending(&id),
        Err(ClipImageFilesError::UnsafePath)
    );
    assert_eq!(
        files.finish_pending(&id),
        Err(ClipImageFilesError::UnsafePath)
    );
    assert_eq!(
        files.pending_file_ids(),
        Err(ClipImageFilesError::UnsafePath)
    );
    assert_eq!(fs::read(outside.join("file")).unwrap(), b"secret");
    fs::remove_file(tree(&directory, &id).join("pending")).unwrap();

    symlink(outside.join("file"), tree(&directory, &id).join("preview")).unwrap();
    assert_eq!(
        files.write_preview(&id, b"x"),
        Err(ClipImageFilesError::UnsafePath)
    );
    assert_eq!(fs::read(outside.join("file")).unwrap(), b"secret");

    symlink(&outside, tree(&directory, OTHER_ID)).unwrap();
    assert_eq!(
        files.validated_original_path(OTHER_ID, 1),
        Err(ClipImageFilesError::UnsafePath)
    );
    fs::remove_file(tree(&directory, OTHER_ID)).unwrap();
    symlink(&missing, tree(&directory, OTHER_ID)).unwrap();
    assert_eq!(files.delete(OTHER_ID), Err(ClipImageFilesError::UnsafePath));
    assert_eq!(
        files.pending_file_ids(),
        Err(ClipImageFilesError::UnsafePath)
    );
    assert_eq!(names(&outside), ["file"]);
}

#[test]
fn a_replaced_root_is_refused() {
    let directory = Directory::new();
    let (files, id) = saved(&directory);
    let outside = directory.0.join("outside");
    fs::create_dir(&outside).unwrap();
    fs::rename(root(&directory), directory.0.join("moved")).unwrap();
    assert_eq!(
        files.pending_file_ids(),
        Err(ClipImageFilesError::UnsafePath)
    );
    symlink(&outside, root(&directory)).unwrap();
    assert_eq!(
        files.pending_file_ids(),
        Err(ClipImageFilesError::UnsafePath)
    );
    assert_eq!(files.delete(&id), Err(ClipImageFilesError::UnsafePath));
}

#[test]
fn identifiers_outside_the_disk_form_are_refused() {
    let directory = Directory::new();
    let files = open(&directory);
    for id in [LOWER_ID, "../outside", "", "11111111"] {
        assert_eq!(files.delete(id), Err(ClipImageFilesError::UnsafePath));
    }
    assert!(names(&root(&directory)).is_empty());
}

#[test]
fn opening_refuses_relative_and_nul_roots() {
    for root in ["relative/images", "/tmp/a\0b"] {
        assert!(matches!(
            ClipImageFiles::open(root.to_string()),
            Err(ClipImageFilesError::InvalidRoot)
        ));
    }
}

#[test]
fn missing_files_and_wrong_sizes_are_distinguished() {
    let directory = Directory::new();
    let files = open(&directory);
    let missing = ClipImageFilesError::NotFound {
        file_id: ID.to_string(),
    };
    assert_eq!(files.validated_original_path(ID, 1), Err(missing.clone()));
    assert_eq!(files.write_preview(ID, b"x"), Err(missing.clone()));
    assert_eq!(files.mark_pending(ID), Ok(()));
    assert_eq!(files.finish_pending(ID), Ok(()));

    let id = files.save(BYTES).unwrap();
    assert_eq!(
        files.validated_original_path(&id, BYTES.len() as i64 + 1),
        Err(ClipImageFilesError::SizeMismatch {
            file_id: id.clone()
        })
    );
    fs::remove_file(tree(&directory, &id).join("original")).unwrap();
    assert_eq!(
        files.validated_original_path(&id, BYTES.len() as i64),
        Err(ClipImageFilesError::NotFound { file_id: id })
    );
}

#[test]
fn derived_files_are_replaced_atomically_and_never_touch_the_original() {
    let directory = Directory::new();
    let (files, id) = saved(&directory);
    let small = files.write_thumbnail(&id, 1, b"small").unwrap();
    let large = files.write_thumbnail(&id, 2, b"large").unwrap();
    assert_ne!(small, large);
    assert!(small.ends_with(&format!("{id}/thumbnail-1")));

    let preserved = directory.0.join("previous");
    fs::hard_link(&small, &preserved).unwrap();
    assert_eq!(files.write_thumbnail(&id, 1, b"newer").unwrap(), small);
    assert_ne!(
        fs::metadata(&preserved).unwrap().ino(),
        fs::metadata(&small).unwrap().ino()
    );
    assert_eq!(fs::read(&preserved).unwrap(), b"small");
    assert_eq!(fs::read(&small).unwrap(), b"newer");

    assert_eq!(
        fs::read(tree(&directory, &id).join("original")).unwrap(),
        BYTES
    );
    assert!(!names(&tree(&directory, &id))
        .iter()
        .any(|name| name.starts_with('.')));
}
