//! 이미지 파일 트리 규칙
//! 이미지마다 `<fileID>/original`, `pending`, `preview`, `thumbnail-<px>`를 둠
//! `preview`와 `thumbnail-<px>`는 원본에서 다시 만들 수 있는 파생 파일
//! 잠금과 캐시 없이 호출마다 디스크를 검사하므로 호출 직렬화는 `ClipImageOperations`가 맡음
//! 프로세스 간 역할 분담은 호스트가 유지
//! 원본 읽기는 호스트가 검사한 경로로 직접 수행

mod error;

use std::fs::{self, File, Metadata, OpenOptions};
use std::io::{self, ErrorKind, Write};
use std::path::{Path, PathBuf};
use std::process;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Arc;

use crate::uuid_form::{is_uuid_form, new_uuid};

pub use error::ClipImageFilesError;

const ORIGINAL: &str = "original";
const PENDING: &str = "pending";
const PREVIEW: &str = "preview";

// 임시 파일 이름의 프로세스 내 순번
static NEXT_TEMPORARY: AtomicU64 = AtomicU64::new(0);

pub struct ClipImageFiles {
    // 반환 경로의 앞부분이므로 호스트가 준 값을 유지
    root: PathBuf,
    // 여는 시점의 실제 경로이며 루트 교체 판정에만 사용
    canonical_root: PathBuf,
}

impl ClipImageFiles {
    /// 없는 루트는 만들고 실제 경로를 기억
    pub fn open(root: String) -> Result<Arc<Self>, ClipImageFilesError> {
        let path = PathBuf::from(&root);
        if !path.is_absolute() || root.contains('\0') {
            return Err(ClipImageFilesError::InvalidRoot);
        }
        fs::create_dir_all(&path).map_err(|_| ClipImageFilesError::WriteFailed)?;
        let canonical_root = canonical(&path)?;
        let files = Self {
            root: path,
            canonical_root,
        };
        files.validate_root()?;
        Ok(Arc::new(files))
    }

    /// 재인코딩 없이 그대로 저장하고 새 식별자를 반환
    /// 같은 폴더가 있으면 새 식별자로 재시도
    /// 정리 표시는 메타데이터 저장 확정 후 호출자가 해제
    pub fn save(&self, data: &[u8]) -> Result<String, ClipImageFilesError> {
        self.validate_root()?;
        loop {
            let file_id = new_uuid().ok_or(ClipImageFilesError::WriteFailed)?;
            if self.create(&file_id, data)? {
                return Ok(file_id);
            }
        }
    }

    pub fn original_path(&self, file_id: &str) -> Result<String, ClipImageFilesError> {
        let (path, _) = self.original(file_id)?;
        Ok(text(&path))
    }

    /// 기록된 크기와 다른 원본은 내용을 읽기 전에 거부
    pub fn validated_original_path(
        &self,
        file_id: &str,
        byte_count: i64,
    ) -> Result<String, ClipImageFilesError> {
        let (path, metadata) = self.original(file_id)?;
        if i64::try_from(metadata.len()) != Ok(byte_count) {
            return Err(ClipImageFilesError::SizeMismatch {
                file_id: file_id.to_string(),
            });
        }
        Ok(text(&path))
    }

    pub fn write_preview(&self, file_id: &str, data: &[u8]) -> Result<String, ClipImageFilesError> {
        self.write_derived(file_id, PREVIEW, data)
    }

    pub fn write_thumbnail(
        &self,
        file_id: &str,
        maximum_pixel_dimension: i64,
        data: &[u8],
    ) -> Result<String, ClipImageFilesError> {
        self.write_derived(
            file_id,
            &format!("thumbnail-{maximum_pixel_dimension}"),
            data,
        )
    }

    /// 이미 없는 파일은 삭제된 것으로 처리
    /// 어느 단계에서 중단되어도 `pending_file_ids`가 다시 찾음
    pub fn delete(&self, file_id: &str) -> Result<(), ClipImageFilesError> {
        let Some(directory) = self.directory(file_id)? else {
            return Ok(());
        };
        self.remove_tree(file_id, &directory)
            .map_err(|_| ClipImageFilesError::DeleteFailed)
    }

    pub fn mark_pending(&self, file_id: &str) -> Result<(), ClipImageFilesError> {
        let Some(directory) = self.directory(file_id)? else {
            return Ok(());
        };
        write_marker(&directory)
    }

    pub fn finish_pending(&self, file_id: &str) -> Result<(), ClipImageFilesError> {
        let Some(directory) = self.directory(file_id)? else {
            return Ok(());
        };
        let marker = directory.join(PENDING);
        if entry(&marker)?.is_none() {
            return Ok(());
        }
        validate_file(&marker)?;
        fs::remove_file(&marker).map_err(|_| ClipImageFilesError::DeleteFailed)
    }

    /// 정상 원본을 일괄 삭제하지 않음
    /// 정리 후보와 저장 중단으로 불완전한 폴더만 반환
    pub fn pending_file_ids(&self) -> Result<Vec<String>, ClipImageFilesError> {
        self.validate_root()?;
        let entries = fs::read_dir(&self.root).map_err(|_| ClipImageFilesError::ReadFailed)?;
        let mut ids = Vec::new();
        for item in entries {
            let item = item.map_err(|_| ClipImageFilesError::ReadFailed)?;
            let name = item.file_name();
            let Some(file_id) = name.to_str().filter(|name| is_file_id(name)) else {
                continue;
            };
            let Some(directory) = self.directory(file_id)? else {
                continue;
            };
            let marker = directory.join(PENDING);
            validate_file(&marker)?;
            if entry(&marker)?.is_some() || entry(&directory.join(ORIGINAL))?.is_none() {
                ids.push(file_id.to_string());
            }
        }
        ids.sort();
        Ok(ids)
    }
}

impl ClipImageFiles {
    // 같은 폴더가 있으면 다른 저장의 폴더이므로 건드리지 않고 false
    fn create(&self, file_id: &str, data: &[u8]) -> Result<bool, ClipImageFilesError> {
        let directory = self.path(file_id)?;
        if entry(&directory)?.is_some() {
            return Ok(false);
        }
        match fs::create_dir(&directory) {
            Err(error) if error.kind() == ErrorKind::AlreadyExists => return Ok(false),
            Err(_) => return Err(ClipImageFilesError::WriteFailed),
            Ok(()) => {}
        }
        if self.write_new(file_id, &directory, data).is_err() {
            // 실패한 정리는 후보 또는 불완전한 폴더로 남아 다음 복구가 처리
            let _ = self.delete(file_id);
            return Err(ClipImageFilesError::WriteFailed);
        }
        Ok(true)
    }

    fn write_new(
        &self,
        file_id: &str,
        directory: &Path,
        data: &[u8],
    ) -> Result<(), ClipImageFilesError> {
        self.mark_pending(file_id)?;
        write_atomically(directory, ORIGINAL, data, true)
            .map_err(|_| ClipImageFilesError::WriteFailed)
    }

    fn write_derived(
        &self,
        file_id: &str,
        name: &str,
        data: &[u8],
    ) -> Result<String, ClipImageFilesError> {
        let directory = self.required_directory(file_id)?;
        let file = directory.join(name);
        validate_file(&file)?;
        write_atomically(&directory, name, data, false)
            .map_err(|_| ClipImageFilesError::WriteFailed)?;
        Ok(text(&file))
    }

    fn remove_tree(&self, file_id: &str, directory: &Path) -> Result<(), ClipImageFilesError> {
        let original = directory.join(ORIGINAL);
        if entry(&original)?.is_some() {
            remove_entry(&original)?;
        }
        for item in fs::read_dir(directory).map_err(delete_failed)? {
            let item = item.map_err(delete_failed)?;
            if item.file_name() != PENDING {
                remove_entry(&item.path())?;
            }
        }
        // 원본과 임시 파일이 모두 제거된 후에만 정리 기록을 해제
        self.finish_pending(file_id)?;
        // 여기서 중단되면 원본이 없는 폴더를 복구 후보로 찾음
        fs::remove_dir_all(directory).map_err(delete_failed)
    }

    fn original(&self, file_id: &str) -> Result<(PathBuf, Metadata), ClipImageFilesError> {
        let original = self.required_directory(file_id)?.join(ORIGINAL);
        let Some(metadata) = entry(&original)? else {
            return Err(not_found(file_id));
        };
        if !metadata.is_file() {
            return Err(ClipImageFilesError::UnsafePath);
        }
        Ok((original, metadata))
    }

    fn required_directory(&self, file_id: &str) -> Result<PathBuf, ClipImageFilesError> {
        self.directory(file_id)?.ok_or_else(|| not_found(file_id))
    }

    fn directory(&self, file_id: &str) -> Result<Option<PathBuf>, ClipImageFilesError> {
        self.validate_root()?;
        let directory = self.path(file_id)?;
        match entry(&directory)? {
            None => Ok(None),
            // 링크의 종류는 폴더가 아니므로 끊어진 링크도 거부
            Some(metadata) if metadata.is_dir() => Ok(Some(directory)),
            Some(_) => Err(ClipImageFilesError::UnsafePath),
        }
    }

    fn path(&self, file_id: &str) -> Result<PathBuf, ClipImageFilesError> {
        if is_file_id(file_id) {
            Ok(self.root.join(file_id))
        } else {
            Err(ClipImageFilesError::UnsafePath)
        }
    }

    // 호스트 경로 표기가 실제 경로와 달라도 맞도록 실제 경로끼리 비교
    fn validate_root(&self) -> Result<(), ClipImageFilesError> {
        if canonical(&self.root)? == self.canonical_root && self.canonical_root.is_dir() {
            Ok(())
        } else {
            Err(ClipImageFilesError::UnsafePath)
        }
    }
}

// 디스크 폴더 이름은 대문자 표기만 허용
fn is_file_id(value: &str) -> bool {
    is_uuid_form(value) && !value.bytes().any(|byte| byte.is_ascii_lowercase())
}

fn not_found(file_id: &str) -> ClipImageFilesError {
    ClipImageFilesError::NotFound {
        file_id: file_id.to_string(),
    }
}

fn canonical(path: &Path) -> Result<PathBuf, ClipImageFilesError> {
    fs::canonicalize(path).map_err(|error| {
        if error.kind() == ErrorKind::NotFound {
            ClipImageFilesError::UnsafePath
        } else {
            ClipImageFilesError::ReadFailed
        }
    })
}

// 호스트가 준 문자열로 만든 경로라 변환 손실 없음
fn text(path: &Path) -> String {
    path.to_string_lossy().into_owned()
}

/// 링크를 따라가지 않는 항목 조회
fn entry(path: &Path) -> Result<Option<Metadata>, ClipImageFilesError> {
    match fs::symlink_metadata(path) {
        Ok(metadata) => Ok(Some(metadata)),
        Err(error) if error.kind() == ErrorKind::NotFound => Ok(None),
        Err(_) => Err(ClipImageFilesError::ReadFailed),
    }
}

fn validate_file(path: &Path) -> Result<(), ClipImageFilesError> {
    match entry(path)? {
        Some(metadata) if !metadata.is_file() => Err(ClipImageFilesError::UnsafePath),
        _ => Ok(()),
    }
}

fn write_marker(directory: &Path) -> Result<(), ClipImageFilesError> {
    validate_file(&directory.join(PENDING))?;
    write_atomically(directory, PENDING, &[], true).map_err(|_| ClipImageFilesError::WriteFailed)
}

// 링크는 대상이 아닌 링크 자체를 제거
fn remove_entry(path: &Path) -> Result<(), ClipImageFilesError> {
    let Some(metadata) = entry(path)? else {
        return Ok(());
    };
    let removed = if metadata.is_dir() {
        fs::remove_dir_all(path)
    } else {
        fs::remove_file(path)
    };
    removed.map_err(delete_failed)
}

fn delete_failed(_: io::Error) -> ClipImageFilesError {
    ClipImageFilesError::DeleteFailed
}

// 같은 폴더의 임시 파일에 쓴 뒤 이름을 바꿈
// 임시 파일이 남아도 `delete`가 `pending` 외 항목을 모두 지움
fn write_atomically(directory: &Path, name: &str, data: &[u8], is_durable: bool) -> io::Result<()> {
    let sequence = NEXT_TEMPORARY.fetch_add(1, Ordering::Relaxed);
    let temporary = directory.join(format!(".{name}.{}-{sequence}", process::id()));
    let written = write_file(&temporary, data, is_durable)
        .and_then(|()| fs::rename(&temporary, directory.join(name)));
    if written.is_err() {
        let _ = fs::remove_file(&temporary);
    }
    written
}

fn write_file(path: &Path, data: &[u8], is_durable: bool) -> io::Result<()> {
    let mut file = OpenOptions::new().write(true).create_new(true).open(path)?;
    file.write_all(data)?;
    if is_durable {
        sync(&file)?;
    }
    Ok(())
}

// `File::sync_all`은 Apple에서 `F_FULLFSYNC`라 기존 Foundation 저장보다 수 배 느림
// 기존 저장과 같은 시간대인 `fsync`를 직접 호출
fn sync(file: &File) -> io::Result<()> {
    rustix::io::retry_on_intr(|| rustix::fs::fsync(file)).map_err(io::Error::from)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn an_existing_folder_is_refused_without_touching_its_files() {
        let root = std::env::temp_dir().join(new_uuid().unwrap());
        let files = ClipImageFiles::open(text(&root)).unwrap();
        let file_id = files.save(b"original").unwrap();

        assert_eq!(files.create(&file_id, b"other"), Ok(false));
        assert_eq!(
            fs::read(files.original_path(&file_id).unwrap()).unwrap(),
            b"original"
        );
        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn new_identifiers_are_version_four_in_the_disk_form() {
        let file_id = new_uuid().unwrap();
        assert!(is_file_id(&file_id));
        assert_eq!(&file_id[14..15], "4");
        assert!(matches!(&file_id[19..20], "8" | "9" | "A" | "B"));
    }
}
