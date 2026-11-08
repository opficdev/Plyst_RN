// 검색 화면의 글자 경계 기준 일치 계산
// JS가 C++ TurboModule과 ffi의 C ABI로 동기 호출하고 UniFFI로는 내보내지 않음

mod clusters;
mod ffi;
mod fold;
mod index;
mod mark_table;
mod text;

pub use self::clusters::{clusters as split_clusters, Cluster};
pub use self::fold::fold as fold_text;
pub use self::index::Index;
pub use self::text::{excerpt_start, matches, ranges, Field};
