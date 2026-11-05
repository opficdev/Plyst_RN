use crate::whitespace::is_whitespace;
use crate::ClipContentValue;

fn has_text(text: &str) -> bool {
    text.chars().any(|c| !is_whitespace(c))
}

// 이미지는 메타데이터만 검증
// 이미지 디코딩과 파일 존재 여부 검사는 이미지 파일 서비스의 책임
pub(crate) fn is_valid(content: &ClipContentValue) -> bool {
    match content {
        ClipContentValue::Text { text } => has_text(text),
        ClipContentValue::Image {
            content_type,
            pixel_width,
            pixel_height,
            byte_count,
            ..
        } => has_text(content_type) && 0 < *pixel_width && 0 < *pixel_height && 0 < *byte_count,
    }
}
