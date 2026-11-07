// 공유받은 텍스트가 내려받을 이미지 주소인지 판정하는 규칙
// iOS의 URL(string:), URLComponents, UTType 판정을 재현
// PlystTests의 ClipShareCoreFoundationTests가 실행 중인 OS의 Foundation 결과와 비교
// 비ASCII 호스트의 IDNA 변환은 재현하지 않으며 입력 그대로 둠

use crate::web_link::is_web_link;
use crate::whitespace::is_whitespace;

/// 응답 형식에 따른 처리
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum ShareResponseKind {
    /// 형식이 이미지라 본문을 코덱으로 검증
    Image,
    /// 형식을 알 수 없어 본문을 코덱으로 판정
    Unknown,
    /// 이미지가 아니라 같은 문자열의 텍스트로 저장
    NotImage,
}

// iOS 27.2 UTType(filenameExtension:)이 이미지로 판정한 확장자
const IMAGE_EXTENSIONS: [&str; 81] = [
    "3fr",
    "ai",
    "arw",
    "avci",
    "avcs",
    "avif",
    "axr",
    "bmp",
    "cr2",
    "cr3",
    "crw",
    "dcm",
    "dcr",
    "dib",
    "dicom",
    "dng",
    "drawing",
    "dxo",
    "efx",
    "erf",
    "exr",
    "fff",
    "fpx",
    "gif",
    "heic",
    "heics",
    "heif",
    "heifs",
    "hif",
    "icns",
    "ico",
    "iiq",
    "j2c",
    "j2k",
    "jfx",
    "jp2",
    "jpe",
    "jpeg",
    "jpf",
    "jpg",
    "jpx",
    "jxl",
    "minc",
    "mnc",
    "mos",
    "mpo",
    "mrw",
    "nef",
    "nefx",
    "nrw",
    "odi",
    "orf",
    "ori",
    "oti",
    "pct",
    "pef",
    "pic",
    "pict",
    "pictclipping",
    "png",
    "pntg",
    "psb",
    "psd",
    "pwl",
    "qti",
    "qtif",
    "raf",
    "raw",
    "rw2",
    "rwl",
    "sgi",
    "sr2",
    "srf",
    "srw",
    "svg",
    "svgz",
    "tga",
    "tif",
    "tiff",
    "webp",
    "xbm",
];

// iOS 27.2 UTType(mimeType:)이 이미지로 판정한 형식
const IMAGE_MEDIA_TYPES: [&str; 69] = [
    "application/dicom",
    "application/photoshop",
    "application/tga",
    "application/vnd.fpx",
    "application/vnd.oasis.opendocument.image",
    "application/vnd.oasis.opendocument.image-template",
    "image/avci",
    "image/avcs",
    "image/avif",
    "image/bmp",
    "image/efax",
    "image/fpx",
    "image/gif",
    "image/heic",
    "image/heic-sequence",
    "image/heif",
    "image/heif-sequence",
    "image/jp2",
    "image/jpeg",
    "image/jpg",
    "image/jxl",
    "image/photoshop",
    "image/pict",
    "image/png",
    "image/psd",
    "image/sgi",
    "image/svg+xml",
    "image/targa",
    "image/tga",
    "image/tiff",
    "image/vnd.adobe.photoshop",
    "image/vnd.microsoft.icon",
    "image/webp",
    "image/x-adobe-dng",
    "image/x-canon-cr2",
    "image/x-canon-cr3",
    "image/x-canon-crw",
    "image/x-canon-tif",
    "image/x-dxo-dxo",
    "image/x-epson-erf",
    "image/x-fuji-raf",
    "image/x-hasselblad-3fr",
    "image/x-hasselblad-fff",
    "image/x-kodak-dcr",
    "image/x-leaf-mos",
    "image/x-leica-pwl",
    "image/x-leica-raw",
    "image/x-leica-rwl",
    "image/x-macpict",
    "image/x-minolta-mrw",
    "image/x-nikon-nef",
    "image/x-nikon-nefx",
    "image/x-nikon-nrw",
    "image/x-olympus-or",
    "image/x-olympus-orf",
    "image/x-olympus-sr",
    "image/x-panasonic-raw",
    "image/x-panasonic-rw2",
    "image/x-pentax-pef",
    "image/x-phaseone-iiq",
    "image/x-photoshop",
    "image/x-pict",
    "image/x-quicktime",
    "image/x-samsung-srw",
    "image/x-sony-arw",
    "image/x-sony-axr",
    "image/x-sony-sr2",
    "image/x-sony-srf",
    "image/x-xbitmap",
];

// iOS URLSession이 본문을 보고 형식을 다시 정하는 응답 형식
const UNKNOWN_MEDIA_TYPES: [&str; 4] = [
    "text/plain",
    "unknown/unknown",
    "application/unknown",
    "*/*",
];

/// 내려받을 주소이자 메모 문자열
/// 웹 링크가 아니거나 공백으로 시작하거나 경로와 쿼리 값에 이미지 확장자가 없으면 None
/// 끝의 공백은 URL(string:)처럼 퍼센트 인코딩해 판정
pub(crate) fn image_url(text: &str) -> Option<String> {
    if text.starts_with(is_whitespace) || !is_web_link(text) {
        return None;
    }
    let url = normalized(text);
    let (path, query) = path_and_query(&url);
    let is_image = has_image_extension(path)
        || query.is_some_and(|query| {
            query_values(query).any(|value| has_image_extension(value_path(&value)))
        });
    is_image.then_some(url)
}

/// Content-Type 헤더 원문의 처리
pub(crate) fn response_kind(content_type: Option<&str>) -> ShareResponseKind {
    let essence = content_type
        .and_then(|value| value.split(';').next())
        .map(|value| value.trim().to_ascii_lowercase())
        .unwrap_or_default();
    if essence.is_empty() || UNKNOWN_MEDIA_TYPES.contains(&essence.as_str()) {
        ShareResponseKind::Unknown
    } else if IMAGE_MEDIA_TYPES.contains(&essence.as_str()) {
        ShareResponseKind::Image
    } else {
        ShareResponseKind::NotImage
    }
}

// URL(string:)의 absoluteString과 같은 표기
// 사용자 정보, 경로, 쿼리, 조각의 허용되지 않는 문자를 대문자 퍼센트 인코딩
// 올바른 퍼센트 인코딩은 그대로 둠
fn normalized(text: &str) -> String {
    let scheme_end = text.find("://").map_or(0, |index| index + 3);
    let (scheme, rest) = text.split_at(scheme_end);
    let authority_end = rest.find(['/', '?', '#']).unwrap_or(rest.len());
    let (authority, rest) = rest.split_at(authority_end);
    let mut url = String::with_capacity(text.len());
    url.push_str(scheme);
    match authority.rsplit_once('@') {
        Some((user, host)) => {
            encode(user, &['@'], &mut url);
            url.push('@');
            url.push_str(host);
        }
        None => url.push_str(authority),
    }
    let (before_fragment, fragment) = match rest.split_once('#') {
        Some((before, fragment)) => (before, Some(fragment)),
        None => (rest, None),
    };
    encode(before_fragment, &[], &mut url);
    if let Some(fragment) = fragment {
        url.push('#');
        encode(fragment, &['#'], &mut url);
    }
    url
}

fn encode(part: &str, extra: &[char], url: &mut String) {
    for (index, c) in part.char_indices() {
        let is_escape = c == '%' && is_escape_at(&part[index + 1..]);
        if is_escape
            || (c.is_ascii() && !c.is_ascii_control() && !is_forbidden(c) && !extra.contains(&c))
        {
            url.push(c);
        } else {
            let mut buffer = [0; 4];
            for byte in c.encode_utf8(&mut buffer).bytes() {
                url.push_str(&format!("%{byte:02X}"));
            }
        }
    }
}

fn is_forbidden(c: char) -> bool {
    matches!(
        c,
        ' ' | '"' | '%' | '<' | '>' | '[' | '\\' | ']' | '^' | '`' | '{' | '|' | '}'
    )
}

fn is_escape_at(text: &str) -> bool {
    let bytes = text.as_bytes();
    bytes.len() >= 2 && bytes[0].is_ascii_hexdigit() && bytes[1].is_ascii_hexdigit()
}

// 정규화한 주소의 경로와 쿼리
fn path_and_query(url: &str) -> (&str, Option<&str>) {
    let rest = &url[url.find("://").map_or(0, |index| index + 3)..];
    let rest = rest.split('#').next().unwrap_or_default();
    let rest = &rest[rest.find(['/', '?']).unwrap_or(rest.len())..];
    match rest.split_once('?') {
        Some((path, query)) => (path, Some(query)),
        None => (rest, None),
    }
}

// URLComponents.queryItems의 값
// 퍼센트 인코딩은 풀고 +는 그대로 둠
fn query_values(query: &str) -> impl Iterator<Item = String> + '_ {
    query
        .split('&')
        .filter_map(|item| item.split_once('=').map(|(_, value)| decoded(value)))
}

// URL(string:)로 해석한 쿼리 값의 경로
fn value_path(value: &str) -> &str {
    let value = value.split('#').next().unwrap_or_default();
    let value = value.split('?').next().unwrap_or_default();
    let rest = match value.find(':') {
        Some(index) if is_scheme(&value[..index]) => &value[index + 1..],
        _ => value,
    };
    match rest.strip_prefix("//") {
        Some(after) => &after[after.find('/').unwrap_or(after.len())..],
        None => rest,
    }
}

fn is_scheme(text: &str) -> bool {
    let mut chars = text.chars();
    chars.next().is_some_and(|c| c.is_ascii_alphabetic())
        && chars.all(|c| c.is_ascii_alphanumeric() || matches!(c, '+' | '-' | '.'))
}

// URL.pathExtension과 같은 판정
// 마지막 경로 구성 요소의 앞쪽 점을 뺀 이름에서 마지막 점 뒤
fn has_image_extension(path: &str) -> bool {
    let decoded = decoded(path);
    let component = decoded
        .trim_end_matches('/')
        .rsplit('/')
        .next()
        .unwrap_or_default()
        .trim_start_matches('.');
    let Some((name, extension)) = component.rsplit_once('.') else {
        return false;
    };
    !name.is_empty()
        && !extension.is_empty()
        && IMAGE_EXTENSIONS
            .iter()
            .any(|image| image.eq_ignore_ascii_case(extension))
}

// 퍼센트 인코딩을 풀고 UTF-8이 아닌 바이트는 대체 문자로 바꿈
fn decoded(text: &str) -> String {
    let bytes = text.as_bytes();
    let mut output = Vec::with_capacity(bytes.len());
    let mut index = 0;
    while index < bytes.len() {
        if bytes[index] == b'%' && is_escape_at(&text[index + 1..]) {
            let value = u8::from_str_radix(&text[index + 1..index + 3], 16).unwrap_or_default();
            output.push(value);
            index += 3;
        } else {
            output.push(bytes[index]);
            index += 1;
        }
    }
    String::from_utf8_lossy(&output).into_owned()
}
