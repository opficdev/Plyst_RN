use crate::whitespace::is_whitespace;

pub(crate) fn is_text_valid(text: &str) -> bool {
    text.chars().any(|c| !is_whitespace(c))
}

// 이미지는 메타데이터만 검증
// 이미지 디코딩과 파일 존재 여부 검사는 이미지 파일 서비스의 책임
pub(crate) fn is_image_valid(
    content_type: &str,
    pixel_width: i64,
    pixel_height: i64,
    byte_count: i64,
) -> bool {
    is_text_valid(content_type) && 0 < pixel_width && 0 < pixel_height && 0 < byte_count
}
