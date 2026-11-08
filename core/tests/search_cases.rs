// 실기기 Swift 원본에서 얻은 검색 기대값과 글자 경계, 발췌 규칙 검증

use std::sync::Arc;

use plyst_core::search::{excerpt_start, fold_text, ranges, split_clusters, Field, Index};
use serde::Deserialize;

#[derive(Deserialize)]
struct Case {
    id: String,
    text: String,
    query: String,
    #[serde(rename = "queryEmpty")]
    query_empty: bool,
    ranges: Vec<[u32; 2]>,
}

#[derive(Deserialize)]
struct Cases {
    cases: Vec<Case>,
}

fn utf16(text: &str) -> Vec<u16> {
    text.encode_utf16().collect()
}

fn sync(index: &Index, order: Vec<Vec<u16>>, updates: Vec<(usize, usize, Vec<u16>)>) {
    let fields = updates
        .into_iter()
        .map(|(position, field, text)| (position, field, Field::new(text)))
        .collect();
    index.sync_fields(order, fields);
}

// JS normalizeSearchQuery와 같은 양끝 공백 집합(clipWhitespace.ts)
fn normalize_query(text: &str) -> String {
    let edge = |c: char| {
        matches!(
            c,
            '\t' | '\n'
                | '\u{0b}'
                | '\u{0c}'
                | '\r'
                | ' '
                | '\u{85}'
                | '\u{a0}'
                | '\u{1680}'
                | '\u{2028}'
                | '\u{2029}'
                | '\u{202f}'
                | '\u{205f}'
                | '\u{3000}'
        ) || ('\u{2000}'..='\u{200a}').contains(&c)
    };
    text.trim_matches(edge).to_string()
}

fn search_ranges(text: &str, query: &str) -> Vec<[u32; 2]> {
    let field = Field::new(utf16(text));
    ranges(&field, &fold_text(&utf16(&normalize_query(query))))
        .into_iter()
        .map(|(location, length)| [location, length])
        .collect()
}

fn slice(text: &str, range: [u32; 2]) -> String {
    let units = utf16(text);
    String::from_utf16(&units[range[0] as usize..(range[0] + range[1]) as usize]).unwrap()
}

#[test]
fn swift_original_cases() {
    let cases: Cases = serde_json::from_str(include_str!("fixtures/search-cases.json")).unwrap();
    assert_eq!(cases.cases.len(), 23);
    for case in cases.cases {
        assert_eq!(
            normalize_query(&case.query).is_empty(),
            case.query_empty,
            "{}",
            case.id
        );
        assert_eq!(
            search_ranges(&case.text, &case.query),
            case.ranges,
            "{}",
            case.id
        );
    }
}

#[test]
fn case_only_and_accents_distinguished() {
    assert_eq!(search_ranges("Scan the QR code", "qr").len(), 1);
    assert_eq!(search_ranges("qr", "qr").len(), 1);
    assert!(search_ranges("q r", "qr").is_empty());
    assert!(search_ranges("Café", "cafe").is_empty());
}

#[test]
fn non_overlapping_ranges() {
    let text = "aaaa AA a";
    let found: Vec<String> = search_ranges(text, "aa")
        .into_iter()
        .map(|range| slice(text, range))
        .collect();
    assert_eq!(found, ["aa", "aa", "AA"]);
}

#[test]
fn no_match_or_empty_text() {
    assert!(search_ranges("abc", "xyz").is_empty());
    assert!(search_ranges("", "xyz").is_empty());
}

#[test]
fn hangul_equivalence_points_to_original() {
    let decomposed = "\u{1112}\u{1161}\u{11ab}\u{1100}\u{1173}\u{11af}";
    let text = format!("앞 {decomposed} 뒤");
    let found = search_ranges(&text, "한글");
    assert_eq!(slice(&text, found[0]), decomposed);
}

#[test]
fn no_match_inside_emoji_or_combining() {
    let text = "👨\u{200d}👩\u{200d}👧 e\u{301}x e";
    let units = utf16(text);
    let mut boundaries: Vec<u32> = split_clusters(&units)
        .iter()
        .map(|cluster| cluster.index as u32)
        .collect();
    boundaries.push(units.len() as u32);
    let found = search_ranges(text, "e");
    assert_eq!(found.len(), 1);
    for range in found {
        assert!(boundaries.contains(&range[0]));
        assert!(boundaries.contains(&(range[0] + range[1])));
    }
}

#[test]
fn fast_and_general_paths_agree() {
    for (text, query) in [
        ("Cat cat CAT", "cat"),
        ("한글 가나다 한글", "한글"),
        ("a\r\nb a\r\nb", "a\r\nb"),
        ("첫째\n둘째\t셋째", "둘째"),
        ("ㄱㄴㄷ ABC", "abc"),
        ("한글 café 한글", "한글"),
    ] {
        let general: Vec<[u32; 2]> = search_ranges(&format!("😀{text}"), query)
            .into_iter()
            .map(|[location, length]| [location - 2, length])
            .collect();
        assert_eq!(search_ranges(text, query), general, "{text}");
    }
}

#[test]
fn unsynced_text_uses_temporary_field() {
    let index = Index::new();
    sync(&index, vec![utf16("a")], vec![(0, 1, utf16("Straße"))]);
    let stored = index.field(&utf16("a"), 1, &utf16("Straße"), true);
    assert_eq!(ranges(&stored, &fold_text(&utf16("ss"))), vec![(4, 1)]);
    assert!(Arc::ptr_eq(
        &stored,
        &index.field(&utf16("a"), 1, &utf16("Straße"), true)
    ));
    let other = index.field(&utf16("a"), 1, &utf16("다른 본문"), false);
    assert!(!Arc::ptr_eq(&stored, &other));
    assert!(ranges(&other, &fold_text(&utf16("ss"))).is_empty());
    let missing = index.field(&utf16("b"), 1, &utf16("ss"), true);
    assert_eq!(ranges(&missing, &fold_text(&utf16("ss"))), vec![(0, 2)]);
}

#[test]
fn joined_sequences_are_one_cluster() {
    for text in [
        "👨\u{200d}👩\u{200d}👧\u{200d}👦",
        "🇰🇷",
        "e\u{301}",
        "a\u{200d}b",
        "\r\n",
    ] {
        assert_eq!(split_clusters(&utf16(text)).len(), 1, "{text}");
    }
}

#[test]
fn excerpt_starts_14_clusters_before_match_after_40() {
    let late = format!("{}target", "가".repeat(50));
    assert_eq!(excerpt_start(&utf16(&late), 50), 36);
    let early = format!("target{}", "가".repeat(50));
    assert_eq!(excerpt_start(&utf16(&early), 0), 0);
    let boundary = format!("{}target", "가".repeat(40));
    assert_eq!(excerpt_start(&utf16(&boundary), 40), 0);
    let emoji = format!("{}target", "😀".repeat(50));
    assert_eq!(excerpt_start(&utf16(&emoji), 100), 72);
    let decomposed = format!("{}target", "\u{1112}\u{1161}\u{11ab}".repeat(50));
    assert_eq!(excerpt_start(&utf16(&decomposed), 150), 108);
}

#[test]
fn filter_follows_text_and_image_branches() {
    let index = Index::new();
    sync(
        &index,
        vec![utf16("text"), utf16("image")],
        vec![
            (0, 0, utf16("이름")),
            (0, 1, utf16("본문 검색")),
            (1, 0, utf16("사진")),
            (1, 2, utf16("오늘 오후 3:00")),
            (1, 3, utf16("2026. 11. 4.")),
        ],
    );
    assert_eq!(index.filter(&utf16("검색")), vec![0]);
    assert_eq!(index.filter(&utf16("오후")), vec![1]);
    assert_eq!(index.filter(&utf16("이름")), vec![0]);
    assert!(index.filter(&utf16("")).is_empty());
}

#[test]
fn prebuild_then_cancel_keeps_results() {
    let index = Index::new();
    let body = "Straße 한글 café".repeat(50);
    let order: Vec<Vec<u16>> = (0..200).map(|i| utf16(&format!("id{i}"))).collect();
    let updates = (0..200).map(|i| (i, 1, utf16(&body))).collect();
    sync(&index, order, updates);
    let before = index.filter(&utf16("ss"));
    index.prebuild();
    index.cancel_prebuild();
    index.prebuild();
    assert_eq!(index.filter(&utf16("ss")), before);
    assert_eq!(before.len(), 200);
}
