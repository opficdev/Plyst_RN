// 클립 규칙의 대표 사례 검증
// Foundation 결과와의 전수 비교는 PlystTests의 ClipCoreFoundationTests가 담당
// 판정 함수는 공개 함수로 호출하므로 테스트 전용 진입점이 없음

use plyst_core::{clip_image_is_valid, clip_text_is_valid, clip_text_is_web_link};

#[test]
fn text_validity_uses_foundation_whitespace() {
    for blank in ["", " \n\t", "\u{200B}", "\u{85}", "\u{3000}\u{2028}"] {
        assert!(!clip_text_is_valid(blank), "{blank:?}");
    }
    for valid in [
        "a", " a ", "\u{1C}", "\u{1F}", "\u{FEFF}", "\u{200D}", " \u{301}",
    ] {
        assert!(clip_text_is_valid(valid), "{valid:?}");
    }
}

#[test]
fn web_link_accepts_foundation_hosts() {
    for link in [
        "https://example.com",
        " HTTP://EXAMPLE.COM/Path\n",
        "https://한글.com",
        "https://exa_mple.com/",
        "https://a..b/",
        "https://example.com/a|b",
        "https://example.com/%zz",
        "https://user:pw@example.com:8080/x",
        "https://[::1]:80/",
        "https://[fe80::1%en0]",
        "https://%41/",
        "https://a:",
    ] {
        assert!(clip_text_is_web_link(link), "{link:?}");
    }
}

#[test]
fn web_link_rejects_foundation_failures() {
    for text in [
        "",
        "example.com",
        "ftp://example.com",
        "https://",
        "https:example.com",
        "https://example.com hello",
        "https://a b/",
        "https://%zz/",
        "https://a|b/",
        "https://a:80a",
        "https://a:b:c/",
        "https://a@/",
        "https://[]/",
        "https://[::1]x",
        "https://[한]/",
        "\u{FEFF}https://a/",
    ] {
        assert!(!clip_text_is_web_link(text), "{text:?}");
    }
}

// IDNA를 재현하지 않아 Foundation과 다른 입력
#[test]
fn web_link_does_not_check_idna() {
    for text in ["https://한-/", "https://-한/", "https://\u{E000}.com/"] {
        assert!(clip_text_is_web_link(text), "{text:?}");
    }
}

#[test]
fn web_link_long_input_stays_valid() {
    assert!(clip_text_is_web_link(&format!(
        "https://example.com/{}",
        "a".repeat(1 << 20)
    )));
    assert!(clip_text_is_web_link(&format!(
        "https://{}.com/",
        "a".repeat(1 << 20)
    )));
}

#[test]
fn image_validity_checks_every_field() {
    assert!(clip_image_is_valid("public.png", 1, 1, 1));
    assert!(!clip_image_is_valid(" \u{200B}\n", 1, 1, 1));
    assert!(!clip_image_is_valid("public.png", 0, 1, 1));
    assert!(!clip_image_is_valid("public.png", 1, -1, 1));
    assert!(!clip_image_is_valid("public.png", 1, 1, 0));
}
