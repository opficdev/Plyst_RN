/// 8-4-4-4-12 형식과 16진수만 허용
/// 대소문자는 구분하지 않음
pub(crate) fn is_uuid_form(value: &str) -> bool {
    let bytes = value.as_bytes();
    bytes.len() == 36
        && bytes.iter().enumerate().all(|(index, byte)| {
            let is_hyphen_position = matches!(index, 8 | 13 | 18 | 23);
            is_hyphen_position == (*byte == b'-')
                && (is_hyphen_position || byte.is_ascii_hexdigit())
        })
}
