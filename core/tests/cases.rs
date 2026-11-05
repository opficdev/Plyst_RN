// iOS Foundation에서 얻은 기대값으로 클립 규칙 검증
// 판정 함수는 공개 함수로 호출하므로 테스트 전용 진입점이 없음

use plyst_core::{
    clip_image_is_valid, clip_pinned_at, clip_sort_order, clip_text_is_valid,
    clip_text_is_web_link, clip_usage_applies, ClipContentValue, ClipIdentity,
};
use serde::Deserialize;

#[derive(Deserialize)]
struct Case {
    input: String,
    expected: bool,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct Cases {
    whitespace: Vec<u32>,
    web_link: Vec<Case>,
    web_link_known_differences: Vec<Case>,
    text_is_valid: Vec<Case>,
}

fn cases() -> Cases {
    serde_json::from_str(include_str!("cases.json")).unwrap()
}

fn text(value: &str) -> ClipContentValue {
    ClipContentValue::Text {
        text: value.to_owned(),
    }
}

fn image() -> ClipContentValue {
    ClipContentValue::Image {
        file_id: "00000000-0000-0000-0000-000000000001".to_owned(),
        content_type: "public.png".to_owned(),
        pixel_width: 1,
        pixel_height: 1,
        byte_count: 1,
    }
}

fn times(values: &[f64]) -> Vec<u8> {
    values
        .iter()
        .flat_map(|value| value.to_le_bytes())
        .collect()
}

fn order(bytes: Vec<u8>) -> Vec<u32> {
    bytes
        .as_chunks::<4>()
        .0
        .iter()
        .map(|chunk| u32::from_le_bytes(*chunk))
        .collect()
}

fn identity(id: &str, content: ClipContentValue, created_at: f64) -> ClipIdentity {
    ClipIdentity {
        id: id.to_owned(),
        content,
        created_at,
    }
}

// 읽기 경로의 판정이므로 표 밖 스칼라가 없어야 함
#[test]
fn whitespace_matches_foundation_for_every_scalar() {
    let whitespace = cases().whitespace;
    assert_eq!(whitespace.len(), 26);
    for scalar in (0..=0x10FFFF).filter_map(char::from_u32) {
        let expected = !whitespace.contains(&(scalar as u32));
        assert_eq!(
            clip_text_is_valid(&scalar.to_string()),
            expected,
            "U+{:04X}",
            scalar as u32
        );
    }
}

#[test]
fn text_validity_matches_foundation() {
    for case in cases().text_is_valid {
        assert_eq!(
            clip_text_is_valid(&case.input),
            case.expected,
            "{:?}",
            case.input
        );
    }
}

#[test]
fn web_link_matches_foundation() {
    for case in cases().web_link {
        assert_eq!(
            clip_text_is_web_link(&case.input),
            case.expected,
            "{:?}",
            case.input
        );
    }
}

#[test]
fn web_link_long_input_matches_foundation() {
    assert!(clip_text_is_web_link(&format!(
        "https://example.com/{}",
        "a".repeat(1 << 20)
    )));
    assert!(clip_text_is_web_link(&format!(
        "https://{}.com/",
        "a".repeat(1 << 20)
    )));
}

// IDNA를 재현하지 않아 Foundation과 다른 입력
// 차이가 사라지거나 늘면 표를 다시 확인해야 하므로 지금 값을 고정
#[test]
fn web_link_known_differences_stay_opposite() {
    let differences = cases().web_link_known_differences;
    assert!(!differences.is_empty());
    for case in differences {
        assert!(!case.input.is_ascii(), "{:?}", case.input);
        assert_ne!(
            clip_text_is_web_link(&case.input),
            case.expected,
            "{:?}",
            case.input
        );
    }
}

#[test]
fn image_validity_checks_every_field() {
    assert!(clip_image_is_valid("public.png", 1, 1, 1));
    assert!(!clip_image_is_valid(" \u{200B}\n", 1, 1, 1));
    assert!(!clip_image_is_valid("public.png", 0, 1, 1));
    assert!(!clip_image_is_valid("public.png", 1, -1, 1));
    assert!(!clip_image_is_valid("public.png", 1, 1, 0));
}

#[test]
fn pinned_at_keeps_existing_time() {
    assert_eq!(clip_pinned_at(None, true, 5.0), Some(5.0));
    assert_eq!(clip_pinned_at(Some(3.0), true, 5.0), Some(3.0));
    assert_eq!(clip_pinned_at(Some(3.0), false, 5.0), None);
    assert_eq!(clip_pinned_at(None, false, 5.0), None);
}

#[test]
fn usage_applies_only_to_same_clip() {
    let current = identity("A", text("a"), 1.0);
    assert!(clip_usage_applies(current.clone(), current.clone()));
    assert!(!clip_usage_applies(
        identity("B", text("a"), 1.0),
        current.clone()
    ));
    assert!(!clip_usage_applies(
        identity("A", text("b"), 1.0),
        current.clone()
    ));
    assert!(!clip_usage_applies(
        identity("A", text("a"), 2.0),
        current.clone()
    ));
    assert!(!clip_usage_applies(identity("A", image(), 1.0), current));
}

#[test]
fn sort_order_is_newest_first_then_id() {
    let id = |byte: u8| [byte; 16];
    let ids = [id(2), id(1), id(3), id(0)].concat();
    assert_eq!(
        order(clip_sort_order(times(&[1.0, 1.0, 2.0, -0.0]), ids)),
        vec![2, 1, 0, 3]
    );
    let ids = [id(2), id(1)].concat();
    assert_eq!(order(clip_sort_order(times(&[0.0, -0.0]), ids)), vec![1, 0]);
}

#[test]
fn sort_order_keeps_input_when_sizes_differ() {
    assert_eq!(
        order(clip_sort_order(times(&[1.0, 2.0]), vec![0; 16])),
        vec![0, 1]
    );
    assert_eq!(order(clip_sort_order(vec![0; 17], vec![0; 32])), vec![0, 1]);
    assert!(clip_sort_order(vec![], vec![]).is_empty());
}
