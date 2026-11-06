use super::id_bytes;
use super::value::ClipValue;
use crate::ClipContentValue;

const IMAGE: u8 = 1;
const NAME: u8 = 1 << 1;
const PINNED_AT: u8 = 1 << 2;
const MEMO: u8 = 1 << 3;
const LAST_USED_AT: u8 = 1 << 4;
const FIXED_SIZE: usize = 16 + 1 + 8;
const STRING_PREFIX_SIZE: usize = 4;

fn put_string(output: &mut Vec<u8>, value: &str) {
    output.extend_from_slice(&(value.len() as u32).to_le_bytes());
    output.extend_from_slice(value.as_bytes());
}

fn optional_size(value: &Option<String>) -> usize {
    value
        .as_ref()
        .map_or(0, |value| STRING_PREFIX_SIZE + value.len())
}

fn size(clip: &ClipValue) -> usize {
    let content = match &clip.content {
        ClipContentValue::Text { text } => STRING_PREFIX_SIZE + text.len(),
        ClipContentValue::Image { content_type, .. } => {
            16 + 24 + STRING_PREFIX_SIZE + content_type.len()
        }
    };
    FIXED_SIZE + content + optional_size(&clip.name) + optional_size(&clip.memo) + 16
}

// 클립마다 식별자 16바이트, 표시 1바이트, 생성 시각, 내용, 있는 선택 필드 순서
// 숫자는 리틀 엔디언이고 문자열은 UTF-8 길이 4바이트와 내용
pub(crate) fn encoded(clips: &[ClipValue]) -> Vec<u8> {
    let mut output = Vec::with_capacity(clips.iter().map(size).sum());
    for clip in clips {
        let mut flags = 0;
        if matches!(clip.content, ClipContentValue::Image { .. }) {
            flags |= IMAGE;
        }
        if clip.name.is_some() {
            flags |= NAME;
        }
        if clip.pinned_at.is_some() {
            flags |= PINNED_AT;
        }
        if clip.memo.is_some() {
            flags |= MEMO;
        }
        if clip.last_used_at.is_some() {
            flags |= LAST_USED_AT;
        }
        output.extend_from_slice(&id_bytes(&clip.id));
        output.push(flags);
        output.extend_from_slice(&clip.created_at.to_le_bytes());
        match &clip.content {
            ClipContentValue::Text { text } => put_string(&mut output, text),
            ClipContentValue::Image {
                file_id,
                content_type,
                pixel_width,
                pixel_height,
                byte_count,
            } => {
                output.extend_from_slice(&id_bytes(file_id));
                output.extend_from_slice(&pixel_width.to_le_bytes());
                output.extend_from_slice(&pixel_height.to_le_bytes());
                output.extend_from_slice(&byte_count.to_le_bytes());
                put_string(&mut output, content_type);
            }
        }
        if let Some(name) = &clip.name {
            put_string(&mut output, name);
        }
        if let Some(pinned_at) = clip.pinned_at {
            output.extend_from_slice(&pinned_at.to_le_bytes());
        }
        if let Some(memo) = &clip.memo {
            put_string(&mut output, memo);
        }
        if let Some(last_used_at) = clip.last_used_at {
            output.extend_from_slice(&last_used_at.to_le_bytes());
        }
    }
    output
}

#[cfg(test)]
mod tests {
    use super::*;

    const ID: &str = "00112233-4455-6677-8899-AABBCCDDEEFF";
    const FILE_ID: &str = "FFEEDDCC-BBAA-9988-7766-554433221100";

    fn clip(content: ClipContentValue) -> ClipValue {
        ClipValue {
            id: ID.to_owned(),
            content,
            name: None,
            pinned_at: None,
            memo: None,
            created_at: 1.5,
            last_used_at: None,
        }
    }

    #[test]
    fn text_without_optional_fields_has_no_extra_bytes() {
        let text = ClipContentValue::Text {
            text: "한".to_owned(),
        };
        let mut expected = id_bytes(ID).to_vec();
        expected.push(0);
        expected.extend_from_slice(&1.5_f64.to_le_bytes());
        expected.extend_from_slice(&3_u32.to_le_bytes());
        expected.extend_from_slice("한".as_bytes());
        assert_eq!(encoded(&[clip(text)]), expected);
    }

    #[test]
    fn image_keeps_every_field_in_order() {
        let mut value = clip(ClipContentValue::Image {
            file_id: FILE_ID.to_owned(),
            content_type: "a".to_owned(),
            pixel_width: 2,
            pixel_height: 3,
            byte_count: 4,
        });
        value.name = Some("b".to_owned());
        value.pinned_at = Some(5.0);
        value.memo = Some("c".to_owned());
        value.last_used_at = Some(6.0);
        let mut expected = id_bytes(ID).to_vec();
        expected.push(IMAGE | NAME | PINNED_AT | MEMO | LAST_USED_AT);
        expected.extend_from_slice(&1.5_f64.to_le_bytes());
        expected.extend_from_slice(&id_bytes(FILE_ID));
        for number in [2_i64, 3, 4] {
            expected.extend_from_slice(&number.to_le_bytes());
        }
        expected.extend_from_slice(&1_u32.to_le_bytes());
        expected.push(b'a');
        expected.extend_from_slice(&1_u32.to_le_bytes());
        expected.push(b'b');
        expected.extend_from_slice(&5.0_f64.to_le_bytes());
        expected.extend_from_slice(&1_u32.to_le_bytes());
        expected.push(b'c');
        expected.extend_from_slice(&6.0_f64.to_le_bytes());
        assert_eq!(encoded(&[value]), expected);
    }
}
