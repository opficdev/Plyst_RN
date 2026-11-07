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

/// UUID 버전 4의 대문자 표기
/// 난수를 얻지 못하면 약한 대체값 없이 None
pub(crate) fn new_uuid() -> Option<String> {
    let mut bytes = [0u8; 16];
    getrandom::fill(&mut bytes).ok()?;
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    let hex: String = bytes.iter().map(|byte| format!("{byte:02X}")).collect();
    Some(format!(
        "{}-{}-{}-{}-{}",
        &hex[..8],
        &hex[8..12],
        &hex[12..16],
        &hex[16..20],
        &hex[20..]
    ))
}
