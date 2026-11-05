// 클립 값 규칙의 공통 코어
// 호스트가 실패를 구분하지 않는 함수는 패닉을 catch_unwind로 막고 정해진 대체값을 돌려줌
// 비던지기 UniFFI 함수의 패닉은 Swift 프로세스를 끝내므로 경계 밖으로 내보내지 않음
// 시각은 2001-01-01 기준 초이고 식별자는 대문자 UUID 문자열

mod content;
mod sort;
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
pub fn clip_content_is_valid(content: ClipContentValue) -> bool {
    guard(true, || content::is_valid(&content))
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

// created_at[i]와 ids[i * 16..][..16]이 같은 클립
// 길이가 맞지 않거나 패닉이면 입력 순서 유지
#[uniffi::export]
pub fn clip_sort_order(created_at: Vec<f64>, ids: Vec<u8>) -> Vec<u32> {
    guard((0..created_at.len() as u32).collect(), || {
        sort::order(&created_at, &ids)
    })
}
