// 최근 검색어의 정규화, 중복 제거, 순서, 개수 규칙
// 첫 요소가 가장 최근

use crate::case_fold::is_same;
use crate::whitespace::trim;

const MAXIMUM_COUNT: usize = 5;

// 공백과 개행뿐이면 None
pub(crate) fn normalized(raw: &str) -> Option<&str> {
    let text = trim(raw);
    (!text.is_empty()).then_some(text)
}

// 저장된 목록이 규칙을 이미 만족할 때만 그대로 반환
pub(crate) fn restored(terms: Vec<String>) -> Option<Vec<String>> {
    if MAXIMUM_COUNT < terms.len() {
        return None;
    }
    for (index, term) in terms.iter().enumerate() {
        if normalized(term) != Some(term.as_str())
            || terms[..index].iter().any(|other| is_same(other, term))
        {
            return None;
        }
    }
    Some(terms)
}

// 같은 항목을 제거하고 새 표기를 맨 앞에 둠
// 최대 개수를 넘으면 가장 오래된 항목을 제거
pub(crate) fn recording(terms: Vec<String>, query: String) -> Vec<String> {
    let mut recorded = Vec::with_capacity(terms.len() + 1);
    recorded.extend(terms.into_iter().filter(|term| !is_same(term, &query)));
    recorded.insert(0, query);
    recorded.truncate(MAXIMUM_COUNT);
    recorded
}

// 정규화 결과가 비었거나 일치하는 항목이 없으면 변경하지 않음
pub(crate) fn removing(terms: Vec<String>, term: &str) -> Vec<String> {
    let Some(query) = normalized(term) else {
        return terms;
    };
    terms
        .into_iter()
        .filter(|other| !is_same(other, query))
        .collect()
}
