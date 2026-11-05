// Foundation URL(string:) 판정을 재현한 호스트 검사
// tests/cases.json이 Foundation 결과를 고정
// 비ASCII 호스트의 IDNA 검사는 재현하지 않으며 아이콘만 달라짐

use crate::whitespace::{is_whitespace, trim};

fn strip_scheme(text: &str) -> Option<&str> {
    ["https://", "http://"].iter().find_map(|scheme| {
        let head = text.get(..scheme.len())?;
        if head.eq_ignore_ascii_case(scheme) {
            text.get(scheme.len()..)
        } else {
            None
        }
    })
}

fn is_host_forbidden(c: char) -> bool {
    c.is_ascii_control()
        || matches!(
            c,
            ' ' | '"' | '<' | '>' | '[' | '\\' | ']' | '^' | '`' | '{' | '|' | '}'
        )
}

fn is_port(text: &str) -> bool {
    text.bytes().all(|byte| byte.is_ascii_digit())
}

// % 뒤는 zone 식별자라 주소 부분만 검사
fn is_ip_literal(text: &str) -> bool {
    let address = text.split('%').next().unwrap_or_default();
    !text.is_empty()
        && address
            .chars()
            .all(|c| c.is_ascii() && !is_host_forbidden(c))
}

fn is_escape(text: &str) -> bool {
    let mut digits = text.chars().take(2);
    digits.next().is_some_and(|c| c.is_ascii_hexdigit())
        && digits.next().is_some_and(|c| c.is_ascii_hexdigit())
}

fn is_host_name(text: &str) -> bool {
    !text.is_empty()
        && text.char_indices().all(|(index, c)| {
            !is_host_forbidden(c) && c != ':' && (c != '%' || is_escape(&text[index + 1..]))
        })
}

pub(crate) fn is_web_link(text: &str) -> bool {
    let trimmed = trim(text);
    if trimmed.is_empty() || trimmed.chars().any(is_whitespace) {
        return false;
    }
    let Some(rest) = strip_scheme(trimmed) else {
        return false;
    };
    let authority = rest.split(['/', '?', '#']).next().unwrap_or_default();
    let host_port = authority.rsplit('@').next().unwrap_or_default();
    if let Some(inner) = host_port.strip_prefix('[') {
        let Some((literal, after)) = inner.split_once(']') else {
            return false;
        };
        return is_ip_literal(literal)
            && (after.is_empty() || after.strip_prefix(':').is_some_and(is_port));
    }
    let (host, port) = host_port.rsplit_once(':').unwrap_or((host_port, ""));
    is_port(port) && is_host_name(host)
}
