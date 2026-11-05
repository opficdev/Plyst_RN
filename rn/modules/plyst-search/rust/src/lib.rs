// plyst_search.h의 C ABI
// 모든 함수는 패닉을 catch_unwind로 막고 실패를 false나 NULL로 알림
// 포인터는 호출하는 동안만 읽고 씀

mod clusters;
mod fold;
mod index;
mod mark_table;
mod text;

use std::ffi::c_void;
use std::panic::{catch_unwind, AssertUnwindSafe};

pub use crate::clusters::{clusters as split_clusters, Cluster};
pub use crate::fold::fold as fold_text;
pub use crate::index::Index;
pub use crate::text::{excerpt_start, matches, ranges, Field};

#[repr(C)]
#[derive(Clone, Copy)]
pub struct PlystSearchText {
    pub data: *const u16,
    pub length: usize,
}

impl PlystSearchText {
    unsafe fn slice(&self) -> &[u16] {
        if self.data.is_null() || self.length == 0 {
            &[]
        } else {
            std::slice::from_raw_parts(self.data, self.length)
        }
    }
}

fn guard<T>(fallback: T, body: impl FnOnce() -> T) -> T {
    catch_unwind(AssertUnwindSafe(body)).unwrap_or(fallback)
}

#[no_mangle]
pub extern "C" fn plyst_search_create() -> *mut Index {
    guard(std::ptr::null_mut(), || {
        Box::into_raw(Box::new(Index::new()))
    })
}

/// # Safety
/// index는 plyst_search_create가 돌려준 값이며 한 번만 해제
#[no_mangle]
pub unsafe extern "C" fn plyst_search_free(index: *mut Index) {
    if !index.is_null() {
        guard((), || drop(Box::from_raw(index)));
    }
}

// sync 한 번 동안 JS 문자열 조각을 바로 받아 필드를 만드는 버퍼
// 텍스트마다 append로 이어 붙인 뒤 id나 field로 확정
pub struct SyncBuilder {
    scratch: Vec<u16>,
    ids: Vec<Vec<u16>>,
    updates: Vec<(usize, usize, Field)>,
}

#[no_mangle]
pub extern "C" fn plyst_search_sync_begin(order_count: usize) -> *mut SyncBuilder {
    guard(std::ptr::null_mut(), || {
        Box::into_raw(Box::new(SyncBuilder {
            scratch: Vec::new(),
            ids: Vec::with_capacity(order_count),
            updates: Vec::new(),
        }))
    })
}

/// # Safety
/// data는 length개의 바이트(ascii) 또는 UTF-16 단위
#[no_mangle]
pub unsafe extern "C" fn plyst_search_sync_append(
    builder: *mut SyncBuilder,
    data: *const c_void,
    length: usize,
    ascii: bool,
) -> bool {
    if builder.is_null() || (data.is_null() && length != 0) {
        return false;
    }
    guard(false, || {
        let scratch = &mut (*builder).scratch;
        if length == 0 {
            return true;
        }
        if ascii {
            let bytes = std::slice::from_raw_parts(data as *const u8, length);
            scratch.extend(bytes.iter().map(|&byte| byte as u16));
        } else {
            scratch.extend_from_slice(std::slice::from_raw_parts(data as *const u16, length));
        }
        true
    })
}

/// # Safety
/// builder는 plyst_search_sync_begin이 돌려준 값
#[no_mangle]
pub unsafe extern "C" fn plyst_search_sync_id(builder: *mut SyncBuilder) -> bool {
    if builder.is_null() {
        return false;
    }
    guard(false, || {
        let builder = &mut *builder;
        builder.ids.push(builder.scratch.clone());
        builder.scratch.clear();
        true
    })
}

/// # Safety
/// builder는 plyst_search_sync_begin이 돌려준 값
#[no_mangle]
pub unsafe extern "C" fn plyst_search_sync_field(
    builder: *mut SyncBuilder,
    position: u32,
    field: u8,
) -> bool {
    if builder.is_null() {
        return false;
    }
    guard(false, || {
        let builder = &mut *builder;
        let value = Field::from_units(&builder.scratch);
        builder
            .updates
            .push((position as usize, field as usize, value));
        builder.scratch.clear();
        true
    })
}

/// # Safety
/// builder는 한 번만 넘기며 이 호출 뒤 쓰지 않음
/// commit이 false면 표를 바꾸지 않고 버림
#[no_mangle]
pub unsafe extern "C" fn plyst_search_sync_end(
    index: *mut Index,
    builder: *mut SyncBuilder,
    commit: bool,
) -> bool {
    if builder.is_null() {
        return false;
    }
    guard(false, || {
        let builder = Box::from_raw(builder);
        if !commit || index.is_null() {
            return !commit;
        }
        (*index).sync_fields(builder.ids, builder.updates);
        true
    })
}

/// # Safety
/// index는 살아 있는 핸들
#[no_mangle]
pub unsafe extern "C" fn plyst_search_prebuild(index: *mut Index) -> bool {
    if index.is_null() {
        return false;
    }
    guard(false, || {
        (*index).prebuild();
        true
    })
}

/// # Safety
/// index는 살아 있는 핸들
#[no_mangle]
pub unsafe extern "C" fn plyst_search_cancel_prebuild(index: *mut Index) {
    if !index.is_null() {
        guard((), || (*index).cancel_prebuild());
    }
}

/// # Safety
/// out 용량은 마지막 sync의 order_count 이상
#[no_mangle]
pub unsafe extern "C" fn plyst_search_filter(
    index: *mut Index,
    query: PlystSearchText,
    out: *mut u32,
    capacity: usize,
    out_count: *mut usize,
) -> bool {
    if index.is_null() || out_count.is_null() {
        return false;
    }
    guard(false, || {
        let result = (*index).filter(query.slice());
        if result.len() > capacity {
            return false;
        }
        if !result.is_empty() {
            std::ptr::copy_nonoverlapping(result.as_ptr(), out, result.len());
        }
        *out_count = result.len();
        true
    })
}

/// # Safety
/// out 용량은 text.length * 2 이상
/// query는 접기 전 질의
/// stored는 text가 마지막 sync로 보낸 값과 같을 때 true
#[no_mangle]
pub unsafe extern "C" fn plyst_search_ranges(
    index: *mut Index,
    id: PlystSearchText,
    field: u8,
    text: PlystSearchText,
    stored: bool,
    query: PlystSearchText,
    out: *mut u32,
    capacity: usize,
    pair_count: *mut usize,
) -> bool {
    if index.is_null() || pair_count.is_null() {
        return false;
    }
    guard(false, || {
        let value = (*index).field(id.slice(), field as usize, text.slice(), stored);
        let found = ranges(&value, &fold_text(query.slice()));
        if found.len() * 2 > capacity {
            return false;
        }
        for (i, (location, length)) in found.iter().enumerate() {
            *out.add(i * 2) = *location;
            *out.add(i * 2 + 1) = *length;
        }
        *pair_count = found.len();
        true
    })
}

/// # Safety
/// body와 start는 유효한 포인터
#[no_mangle]
pub unsafe extern "C" fn plyst_search_excerpt_start(
    body: PlystSearchText,
    location: u32,
    start: *mut u32,
) -> bool {
    if start.is_null() {
        return false;
    }
    guard(false, || {
        *start = excerpt_start(body.slice(), location);
        true
    })
}
