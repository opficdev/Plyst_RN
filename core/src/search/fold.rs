// 대소문자 접기와 빠른 경로 판정
// JS normalize('NFC').toUpperCase()와 같은 결과

use unicode_normalization::UnicodeNormalization;

// ASCII 출력 문자, 개행, 탭, 한글 음절, 호환 자모
pub fn is_simple(text: &[u16]) -> bool {
    text.iter().all(|&unit| {
        (0x20..=0x7e).contains(&unit)
            || unit == 0x0a
            || unit == 0x0d
            || unit == 0x09
            || (0xac00..=0xd7a3).contains(&unit)
            || (0x3131..=0x318e).contains(&unit)
    })
}

// 글자 묶음 하나를 접어 out에 붙이고 늘어난 길이를 돌려줌
// ASCII 한 단위, 한글 음절, 호환 자모는 NFC로 바뀌지 않아 할당 없이 대문자만 적용
pub fn fold_cluster(segment: &[u16], out: &mut Vec<u16>) -> usize {
    if let [unit] = segment {
        let unit = *unit;
        if unit < 0x80 || (0xac00..=0xd7a3).contains(&unit) || (0x3131..=0x318e).contains(&unit) {
            out.push(if (0x61..=0x7a).contains(&unit) {
                unit - 0x20
            } else {
                unit
            });
            return 1;
        }
    }
    let folded = fold(segment);
    out.extend_from_slice(&folded);
    folded.len()
}

// 짝 없는 서로게이트가 있으면 JS처럼 그 단위는 그대로 두고 나머지만 정규화
pub fn fold(text: &[u16]) -> Vec<u16> {
    match String::from_utf16(text) {
        Ok(value) => value
            .nfc()
            .collect::<String>()
            .to_uppercase()
            .encode_utf16()
            .collect(),
        Err(_) => fold_with_lone_surrogates(text),
    }
}

fn fold_with_lone_surrogates(text: &[u16]) -> Vec<u16> {
    let mut result = Vec::with_capacity(text.len());
    let mut start = 0;
    let mut offset = 0;
    while offset < text.len() {
        let (_, len) = super::clusters::next_point(text, offset);
        let unit = text[offset];
        if len == 1 && (0xd800..=0xdfff).contains(&unit) {
            if start < offset {
                result.extend(fold(&text[start..offset]));
            }
            result.push(unit);
            start = offset + 1;
        }
        offset += len;
    }
    if start < text.len() {
        result.extend(fold(&text[start..]));
    }
    result
}
