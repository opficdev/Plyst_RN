// UTF-16 글자 분할
// UAX #29가 아니라 앱의 기존 검색 결과를 유지하는 손 작성 규칙

use crate::mark_table::MARK_RANGES;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Cluster {
    pub index: usize,
    pub len: usize,
}

#[derive(Clone, Copy, PartialEq, Eq)]
enum Hangul {
    None,
    L,
    V,
    T,
    Lv,
    Lvt,
}

fn hangul_kind(point: u32) -> Hangul {
    if (0x1100..=0x115f).contains(&point) || (0xa960..=0xa97c).contains(&point) {
        return Hangul::L;
    }
    if (0x1160..=0x11a7).contains(&point) || (0xd7b0..=0xd7c6).contains(&point) {
        return Hangul::V;
    }
    if (0x11a8..=0x11ff).contains(&point) || (0xd7cb..=0xd7fb).contains(&point) {
        return Hangul::T;
    }
    if (0xac00..=0xd7a3).contains(&point) {
        return if (point - 0xac00).is_multiple_of(28) {
            Hangul::Lv
        } else {
            Hangul::Lvt
        };
    }
    Hangul::None
}

pub(crate) fn is_mark(point: u32) -> bool {
    MARK_RANGES
        .binary_search_by(|&(start, end)| {
            if end < point {
                std::cmp::Ordering::Less
            } else if point < start {
                std::cmp::Ordering::Greater
            } else {
                std::cmp::Ordering::Equal
            }
        })
        .is_ok()
}

// JS의 for...of와 같이 서로게이트 쌍은 한 코드 포인트
// 짝 없는 서로게이트는 그 값 그대로
pub(crate) fn next_point(text: &[u16], offset: usize) -> (u32, usize) {
    let unit = text[offset];
    if (0xd800..=0xdbff).contains(&unit) && offset + 1 < text.len() {
        let low = text[offset + 1];
        if (0xdc00..=0xdfff).contains(&low) {
            let point = 0x10000 + (((unit as u32) - 0xd800) << 10) + ((low as u32) - 0xdc00);
            return (point, 2);
        }
    }
    (unit as u32, 1)
}

pub fn clusters(text: &[u16]) -> Vec<Cluster> {
    let mut result: Vec<Cluster> = Vec::new();
    let mut offset = 0;
    let mut previous = 0u32;
    let mut regional_count = 0usize;
    while offset < text.len() {
        let (code, len) = next_point(text, offset);
        let regional = (0x1f1e6..=0x1f1ff).contains(&code);
        let a = hangul_kind(previous);
        let b = hangul_kind(code);
        let hangul = (a == Hangul::L
            && matches!(b, Hangul::L | Hangul::V | Hangul::Lv | Hangul::Lvt))
            || (matches!(a, Hangul::Lv | Hangul::V) && matches!(b, Hangul::V | Hangul::T))
            || (matches!(a, Hangul::Lvt | Hangul::T) && b == Hangul::T);
        // 짝 없는 서로게이트는 JS 정규식 \p{M}과 같이 Mark가 아님
        let mark = !(0xd800..=0xdfff).contains(&code) && is_mark(code);
        let extend = mark
            || code == 0x200d
            || previous == 0x200d
            || (0xfe00..=0xfe0f).contains(&code)
            || (0xe0100..=0xe01ef).contains(&code)
            || (0x1f3fb..=0x1f3ff).contains(&code)
            || hangul
            || (regional && regional_count % 2 == 1)
            || (previous == 13 && code == 10);
        match result.last_mut() {
            Some(last) if extend => last.len += len,
            _ => result.push(Cluster { index: offset, len }),
        }
        regional_count = if regional { regional_count + 1 } else { 0 };
        previous = code;
        offset += len;
    }
    result
}
