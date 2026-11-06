// 최근 검색어 규칙의 대표 사례 검증
// Foundation 결과와의 전수 비교는 PlystTests의 ClipSearchCoreFoundationTests가 담당
// 같은 항목 판정은 복원 함수의 결과로 확인하고 기록과 삭제는 ClipStore로 호출하므로 테스트 전용 진입점이 없음

mod support;

use std::sync::Arc;

use plyst_core::store::ClipStore;
use plyst_core::{clip_search_history_restored, clip_search_query_normalized};
use support::{open, Directory};

fn terms(values: &[&str]) -> Vec<String> {
    values.iter().map(|value| (*value).to_owned()).collect()
}

fn query(raw: &str) -> Option<String> {
    clip_search_query_normalized(raw).unwrap()
}

// 첫 요소가 가장 최근이 되도록 오래된 항목부터 기록
fn seeded(directory: &Directory, values: &[&str]) -> Arc<ClipStore> {
    let store = open(&directory.database());
    for value in values.iter().rev() {
        store.record_search_term((*value).to_owned()).unwrap();
    }
    store
}

fn record(values: &[&str], term: &str) -> Vec<String> {
    let directory = Directory::new();
    seeded(&directory, values)
        .record_search_term(term.to_owned())
        .unwrap()
}

fn remove(values: &[&str], term: &str) -> Vec<String> {
    let directory = Directory::new();
    seeded(&directory, values)
        .remove_search_term(term.to_owned())
        .unwrap()
}

fn restore(values: &[&str]) -> Option<Vec<String>> {
    clip_search_history_restored(terms(values)).unwrap()
}

fn is_same(lhs: &str, rhs: &str) -> bool {
    restore(&[lhs, rhs]).is_none()
}

#[test]
fn query_trims_and_rejects_blank_input() {
    assert_eq!(query("  Swift \n").as_deref(), Some("Swift"));
    assert_eq!(query(""), None);
    assert_eq!(query(" \n\t "), None);
}

#[test]
fn query_uses_foundation_whitespace() {
    assert_eq!(query("\u{200B}"), None);
    assert_eq!(query("\u{85}"), None);
    assert_eq!(query("\u{1C}").as_deref(), Some("\u{1C}"));
    assert_eq!(query("\u{1F}").as_deref(), Some("\u{1F}"));
    assert_eq!(query("\u{180E}").as_deref(), Some("\u{180E}"));
    assert_eq!(query(" \u{301}a ").as_deref(), Some("\u{301}a"));
}

#[test]
fn same_term_follows_canonical_caseless_matching() {
    assert!(is_same("qr", "QR"));
    assert!(is_same(
        "한글",
        "\u{1112}\u{1161}\u{11AB}\u{1100}\u{1173}\u{11AF}"
    ));
    assert!(is_same("ß", "SS"));
    assert!(is_same("ẞ", "ß"));
    assert!(is_same("ﬁ", "FI"));
    assert!(is_same("a\u{323}\u{307}", "a\u{307}\u{323}"));
    assert!(!is_same("İ", "i"));
    assert!(!is_same("I", "ı"));
    assert!(!is_same("a\u{200B}b", "ab"));
    assert!(!is_same("か", "カ"));
}

// Foundation은 세 쌍을 같다고 보지만 복원 규칙을 깨지 않는 방향이라 표준 규칙을 유지
#[test]
fn same_term_keeps_standard_result_where_foundation_differs() {
    assert!(!is_same("\u{1FB3}\u{307}", "\u{391}\u{399}\u{307}"));
    assert!(!is_same("\u{915}", "\u{958}"));
    assert!(!is_same(
        "\u{1100}\u{1161}\u{FEFF}",
        "\u{AC00}\u{1161}\u{FEFF}"
    ));
}

#[test]
fn record_keeps_newest_first_and_new_spelling() {
    assert_eq!(record(&["first"], "second"), terms(&["second", "first"]));
    assert_eq!(record(&["swift", "qr"], "QR"), terms(&["QR", "swift"]));
}

#[test]
fn record_keeps_at_most_five_terms() {
    let current = ["5", "4", "3", "2", "1"];
    assert_eq!(record(&current, "6"), terms(&["6", "5", "4", "3", "2"]));
    assert_eq!(record(&current, "3"), terms(&["3", "5", "4", "2", "1"]));
}

#[test]
fn remove_matches_after_normalizing() {
    assert_eq!(remove(&["Beta", "alpha"], "BETA"), terms(&["alpha"]));
    assert_eq!(remove(&["alpha"], " alpha "), terms(&[]));
}

#[test]
fn remove_ignores_missing_and_blank_terms() {
    assert_eq!(remove(&["alpha"], "missing"), terms(&["alpha"]));
    assert_eq!(remove(&["alpha"], "   "), terms(&["alpha"]));
}

#[test]
fn restore_accepts_only_valid_terms() {
    assert_eq!(restore(&["b", "a"]), Some(terms(&["b", "a"])));
    assert_eq!(restore(&[]), Some(terms(&[])));
    assert_eq!(restore(&["a", "A"]), None);
    assert_eq!(restore(&["1", "2", "3", "4", "5", "6"]), None);
    assert_eq!(restore(&[" padded "]), None);
    assert_eq!(restore(&[""]), None);
}
