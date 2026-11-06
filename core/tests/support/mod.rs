#![allow(dead_code)]

use std::fs;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicUsize, Ordering};

use plyst_core::store::{ClipContentValue, ClipStore, ClipStoreError, ClipValue};
use plyst_core::ClipIdentity;
use rusqlite::Connection;

static NEXT: AtomicUsize = AtomicUsize::new(0);

pub const CORRUPTED: ClipStoreError = ClipStoreError::CorruptedData {
    code: 0,
    extended_code: 0,
};

/// 시험마다 지워지는 임시 디렉터리
pub struct Directory(pub PathBuf);

impl Directory {
    pub fn new() -> Self {
        let path = std::env::temp_dir().join(format!(
            "plyst-core-{}-{}",
            std::process::id(),
            NEXT.fetch_add(1, Ordering::Relaxed)
        ));
        fs::create_dir_all(&path).unwrap();
        Self(path)
    }

    pub fn database(&self) -> String {
        self.0.join("clips.sqlite").to_str().unwrap().to_string()
    }

    pub fn copy_fixture(&self, name: &str) -> String {
        let source = Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("tests/fixtures")
            .join(name);
        for entry in fs::read_dir(source).unwrap() {
            let entry = entry.unwrap();
            fs::copy(entry.path(), self.0.join(entry.file_name())).unwrap();
        }
        self.database()
    }
}

impl Drop for Directory {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.0);
    }
}

pub fn open(path: &str) -> std::sync::Arc<ClipStore> {
    ClipStore::open(path.to_string()).unwrap()
}

/// 코어 밖의 별도 연결로 저장값을 바꾸어 실패를 재현
pub fn execute(path: &str, sql: &str) {
    Connection::open(path).unwrap().execute_batch(sql).unwrap();
}

pub fn text(id: &str, value: &str) -> ClipValue {
    ClipValue {
        id: id.to_string(),
        content: ClipContentValue::Text {
            text: value.to_string(),
        },
        name: None,
        pinned_at: None,
        memo: None,
        created_at: 793109282.0612345,
        last_used_at: None,
    }
}

pub fn image(id: &str, file_id: &str) -> ClipValue {
    ClipValue {
        content: ClipContentValue::Image {
            file_id: file_id.to_string(),
            content_type: "public.png".to_string(),
            pixel_width: 640,
            pixel_height: 480,
            byte_count: 4096,
        },
        ..text(id, "")
    }
}

pub fn identity(clip: &ClipValue) -> ClipIdentity {
    ClipIdentity {
        id: clip.id.clone(),
        content: clip.content.clone(),
        created_at: clip.created_at,
    }
}
