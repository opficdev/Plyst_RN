// 최근 검색어의 같은 항목 판정
// Unicode 정준 대소문자 무시 일치 NFD(toCasefold(NFD(X)))
// 검색 일치의 NFC와 대문자 접기와는 일부러 다른 규칙

use crate::case_fold_table::CASE_FOLDING;
use unicode_normalization::UnicodeNormalization;

pub(crate) fn is_same(lhs: &str, rhs: &str) -> bool {
    key(lhs) == key(rhs)
}

fn key(text: &str) -> String {
    let mut folded = String::with_capacity(text.len());
    for c in text.nfd() {
        match CASE_FOLDING.binary_search_by_key(&c, |entry| entry.0) {
            Ok(index) => folded.push_str(CASE_FOLDING[index].1),
            Err(_) => folded.push(c),
        }
    }
    folded.nfd().collect()
}
