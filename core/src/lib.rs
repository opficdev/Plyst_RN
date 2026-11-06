// 클립 값 규칙의 공통 코어
// 클립 저장소는 store 모듈이 소유
// 호스트가 실패를 구분하지 않는 함수는 패닉을 catch_unwind로 막고 정해진 대체값을 돌려줌
// 비던지기 UniFFI 함수의 패닉은 Swift 프로세스를 끝내므로 경계 밖으로 내보내지 않음
// 호스트가 실패를 구분해야 하는 함수는 Result를 돌려주어 패닉을 오류로 전달
// 시각은 2001-01-01 기준 초이고 식별자는 대문자 UUID 문자열

mod case_fold;
mod case_fold_table;
mod content;
mod search_history;
mod sort;
pub mod store;
mod update;
mod web_link;
mod whitespace;

use std::panic::{catch_unwind, AssertUnwindSafe};

uniffi::setup_scaffolding!();

#[derive(Clone, Debug, PartialEq, uniffi::Enum)]
pub enum ClipContentValue {
    Text {
        text: String,
    },
    Image {
        file_id: String,
        content_type: String,
        pixel_width: i64,
        pixel_height: i64,
        byte_count: i64,
    },
}

#[derive(Clone, Debug, PartialEq, uniffi::Record)]
pub struct ClipIdentity {
    pub id: String,
    pub content: ClipContentValue,
    pub created_at: f64,
}

fn guard<T>(fallback: T, body: impl FnOnce() -> T) -> T {
    catch_unwind(AssertUnwindSafe(body)).unwrap_or(fallback)
}

// 패닉 때는 아이콘만 달라지므로 false
#[uniffi::export]
pub fn clip_text_is_web_link(text: &str) -> bool {
    guard(false, || web_link::is_web_link(text))
}

// false는 읽기 실패로 이어져 홈 전체를 막으므로 패닉 때는 true
#[uniffi::export]
pub fn clip_text_is_valid(text: &str) -> bool {
    guard(true, || content::is_text_valid(text))
}

#[uniffi::export]
pub fn clip_image_is_valid(
    content_type: &str,
    pixel_width: i64,
    pixel_height: i64,
    byte_count: i64,
) -> bool {
    guard(true, || {
        content::is_image_valid(content_type, pixel_width, pixel_height, byte_count)
    })
}

// 패닉 때는 고정 시각을 잃지 않도록 current 유지
#[uniffi::export]
pub fn clip_pinned_at(current: Option<f64>, is_pinned: bool, requested_at: f64) -> Option<f64> {
    guard(current, || {
        update::pinned_at(current, is_pinned, requested_at)
    })
}

// 패닉 때는 사용 시각을 쓰지 않음
#[uniffi::export]
pub fn clip_usage_applies(expected: ClipIdentity, current: ClipIdentity) -> bool {
    guard(false, || update::usage_applies(&expected, &current))
}

// created_at은 f64 8바이트, ids는 UUID 16바이트, 결과는 u32 4바이트의 리틀 엔디언 나열
// 길이가 맞지 않거나 패닉이면 입력 순서 유지
#[uniffi::export]
pub fn clip_sort_order(created_at: Vec<u8>, ids: Vec<u8>) -> Vec<u8> {
    guard(sort::input_order(created_at.len() / 8), || {
        sort::encoded_order(&created_at, &ids)
    })
}

// 호스트가 실패를 구분해야 하는 함수의 오류
// 패닉은 UniFFI가 호출부의 오류로 바꾸므로 이 값을 직접 만드는 경로는 없음
#[derive(Debug, uniffi::Error)]
#[uniffi(flat_error)]
pub enum CoreError {
    Internal,
}

impl std::fmt::Display for CoreError {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter.write_str("internal")
    }
}

impl std::error::Error for CoreError {}

// 공백과 개행뿐이면 None
#[uniffi::export]
pub fn clip_search_query_normalized(raw: &str) -> Result<Option<String>, CoreError> {
    Ok(search_history::normalized(raw).map(str::to_owned))
}

// None은 저장값의 규칙 위반이고 패닉은 오류로 구분
#[uniffi::export]
pub fn clip_search_history_restored(terms: Vec<String>) -> Result<Option<Vec<String>>, CoreError> {
    Ok(search_history::restored(terms))
}

// query는 정규화가 끝난 값
#[uniffi::export]
pub fn clip_search_history_recording(
    terms: Vec<String>,
    query: String,
) -> Result<Vec<String>, CoreError> {
    Ok(search_history::recording(terms, query))
}

#[uniffi::export]
pub fn clip_search_history_removing(
    terms: Vec<String>,
    term: &str,
) -> Result<Vec<String>, CoreError> {
    Ok(search_history::removing(terms, term))
}
