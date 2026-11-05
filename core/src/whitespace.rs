// Foundation whitespacesAndNewlines와 같은 집합
// tests/cases.json이 Foundation 전수 대조 결과를 고정

pub(crate) fn is_whitespace(c: char) -> bool {
    matches!(
        c,
        '\u{9}'..='\u{D}'
            | ' '
            | '\u{85}'
            | '\u{A0}'
            | '\u{1680}'
            | '\u{2000}'..='\u{200B}'
            | '\u{2028}'
            | '\u{2029}'
            | '\u{202F}'
            | '\u{205F}'
            | '\u{3000}'
    )
}

pub(crate) fn trim(text: &str) -> &str {
    text.trim_matches(is_whitespace)
}
