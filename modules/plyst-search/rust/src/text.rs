// 글자 경계 기준 일치, 범위, 발췌 시작 위치 계산
// 빠른 경로 필드는 접은 텍스트를 1~2바이트 부호로 두고 원문은 두지 않음
// 일반 필드는 맵을 만든 뒤 원문을 버림

use std::sync::{Mutex, MutexGuard, OnceLock};

use crate::clusters::clusters;
use crate::fold::{fold_cluster, is_simple};

// 위치마다 1비트
struct Bits(Box<[u64]>);

fn bit_words(len: usize) -> Vec<u64> {
    vec![0u64; len.div_ceil(64)]
}

fn set_bit(words: &mut [u64], index: usize) {
    words[index >> 6] |= 1 << (index & 63);
}

impl Bits {
    fn get(&self, index: usize) -> bool {
        (self.0[index >> 6] >> (index & 63)) & 1 == 1
    }
}

// 원문 길이가 65,536 미만이면 u16
enum Offsets {
    Narrow(Box<[u16]>),
    Wide(Box<[u32]>),
}

impl Offsets {
    fn get(&self, index: usize) -> u32 {
        match self {
            Offsets::Narrow(values) => values[index] as u32,
            Offsets::Wide(values) => values[index],
        }
    }
}

pub struct ClusterMap {
    starts: Offsets,
    ends: Offsets,
    boundaries: Bits,
}

struct GeneralText {
    folded: Box<[u16]>,
    map: OnceLock<ClusterMap>,
}

// 접기와 맵을 만들 때까지 원문을 둠
pub struct GeneralField {
    original: Mutex<Option<Box<[u16]>>>,
    prepared: OnceLock<GeneralText>,
}

// 빠른 경로 필드는 접은 텍스트 부호만 둠
// 빠른 경로 문자는 UTF-16 한 단위이므로 글자 수가 곧 UTF-16 위치
// ASCII는 1바이트, 한글 음절과 호환 자모는 0x80 이상 앞 바이트와 뒤 바이트
pub enum Field {
    Simple(Box<[u8]>),
    General(Box<GeneralField>),
}

// 오염된 잠금도 안의 값을 그대로 씀
fn lock<T>(mutex: &Mutex<T>) -> MutexGuard<'_, T> {
    mutex
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner())
}

impl GeneralField {
    fn prepared(&self) -> &GeneralText {
        self.prepared.get_or_init(|| {
            let original = lock(&self.original);
            GeneralText {
                folded: fold_general(original.as_deref().unwrap_or(&[])).into_boxed_slice(),
                map: OnceLock::new(),
            }
        })
    }

    fn map<'a>(&'a self, general: &'a GeneralText) -> &'a ClusterMap {
        general.map.get_or_init(|| {
            // 패닉이 나도 다음 시도가 같은 원문을 쓰도록 맵을 만든 뒤에 비움
            let mut original = lock(&self.original);
            let map = build_map(original.as_deref().unwrap_or(&[]), general.folded.len());
            *original = None;
            map
        })
    }
}

impl Field {
    pub fn new(original: Vec<u16>) -> Self {
        Field::from_units(&original)
    }

    pub fn from_units(text: &[u16]) -> Self {
        if is_simple(text) {
            Field::Simple(encode_simple(text))
        } else {
            Field::General(Box::new(GeneralField {
                original: Mutex::new(Some(text.into())),
                prepared: OnceLock::new(),
            }))
        }
    }

    // prebuild가 만드는 범위와 같음
    // 빠른 경로는 만들 것이 없음
    pub fn build_ahead(&self) {
        if let Field::General(general) = self {
            general.map(general.prepared());
        }
    }
}

// 빠른 경로 문자가 아니면 None
fn encode_unit(unit: u16, out: &mut Vec<u8>) -> bool {
    if unit < 0x80 {
        out.push(unit as u8);
        return true;
    }
    let code = if (0xac00..=0xd7a3).contains(&unit) {
        unit - 0xac00
    } else if (0x3131..=0x318e).contains(&unit) {
        11172 + unit - 0x3131
    } else {
        return false;
    };
    out.push(0x80 | (code >> 8) as u8);
    out.push(code as u8);
    true
}

// 빠른 경로 문자 중 대소문자가 있는 것은 ASCII 소문자뿐
// 임시 버퍼 없이 정확한 크기로 한 번에 채움
fn encode_simple(text: &[u16]) -> Box<[u8]> {
    let length = text.len() + text.iter().filter(|&&unit| 0x80 <= unit).count();
    let mut bytes = vec![0u8; length].into_boxed_slice();
    let mut offset = 0;
    for &unit in text {
        if unit < 0x80 {
            bytes[offset] = if (0x61..=0x7a).contains(&unit) {
                (unit - 0x20) as u8
            } else {
                unit as u8
            };
            offset += 1;
        } else {
            let code = if 0xac00 <= unit {
                unit - 0xac00
            } else {
                11172 + unit - 0x3131
            };
            bytes[offset] = 0x80 | (code >> 8) as u8;
            bytes[offset + 1] = code as u8;
            offset += 2;
        }
    }
    bytes
}

fn encode_query(query: &[u16]) -> Option<Vec<u8>> {
    let mut bytes = Vec::with_capacity(query.len());
    for &unit in query {
        if !encode_unit(unit, &mut bytes) {
            return None;
        }
    }
    Some(bytes)
}

// 접은 길이는 원문과 다를 수 있어 Vec으로 모은 뒤 줄임
fn fold_general(text: &[u16]) -> Vec<u16> {
    let mut folded = Vec::with_capacity(text.len());
    for cluster in clusters(text) {
        fold_cluster(
            &text[cluster.index..cluster.index + cluster.len],
            &mut folded,
        );
    }
    folded
}

// 위치 표는 처음부터 최종 폭으로 만들어 옮겨 담지 않음
fn fill_map<T: Copy + Default>(
    original: &[u16],
    folded_len: usize,
    convert: impl Fn(usize) -> T,
) -> (Box<[T]>, Box<[T]>, Bits) {
    let mut starts = vec![T::default(); folded_len].into_boxed_slice();
    let mut ends = vec![T::default(); folded_len].into_boxed_slice();
    let mut boundaries = bit_words(folded_len + 1).into_boxed_slice();
    let mut offset = 0;
    let mut scratch = Vec::new();
    for cluster in clusters(original) {
        scratch.clear();
        let length = fold_cluster(
            &original[cluster.index..cluster.index + cluster.len],
            &mut scratch,
        );
        set_bit(&mut boundaries, offset);
        starts[offset..offset + length].fill(convert(cluster.index));
        ends[offset..offset + length].fill(convert(cluster.index + cluster.len));
        offset += length;
        set_bit(&mut boundaries, offset);
    }
    (starts, ends, Bits(boundaries))
}

fn build_map(original: &[u16], folded_len: usize) -> ClusterMap {
    if original.len() <= u16::MAX as usize {
        let (starts, ends, boundaries) = fill_map(original, folded_len, |value| value as u16);
        ClusterMap {
            starts: Offsets::Narrow(starts),
            ends: Offsets::Narrow(ends),
            boundaries,
        }
    } else {
        let (starts, ends, boundaries) = fill_map(original, folded_len, |value| value as u32);
        ClusterMap {
            starts: Offsets::Wide(starts),
            ends: Offsets::Wide(ends),
            boundaries,
        }
    }
}

// JS String.prototype.indexOf(query, cursor)와 같은 UTF-16 첫 위치
fn index_of(haystack: &[u16], needle: &[u16], from: usize) -> Option<usize> {
    if needle.len() > haystack.len() {
        return None;
    }
    let first = needle[0];
    let last_start = haystack.len() - needle.len();
    let mut position = from;
    while position <= last_start {
        if haystack[position] == first && haystack[position..position + needle.len()] == *needle {
            return Some(position);
        }
        position += 1;
    }
    None
}

// 글자 시작만 차례로 밟으므로 UTF-16 indexOf와 같은 위치
// from은 글자 시작
// (일치 바이트 위치, 건너뛴 글자 수) 반환
fn simple_index_of(bytes: &[u8], needle: &[u8], from: usize) -> Option<(usize, usize)> {
    if needle.len() > bytes.len() {
        return None;
    }
    let first = needle[0];
    let last_start = bytes.len() - needle.len();
    let mut position = from;
    let mut skipped = 0;
    while position <= last_start {
        if bytes[position] == first && bytes[position..position + needle.len()] == *needle {
            return Some((position, skipped));
        }
        position += if bytes[position] < 0x80 { 1 } else { 2 };
        skipped += 1;
    }
    None
}

// (location, length, next cursor)
fn general_first(
    field: &GeneralField,
    general: &GeneralText,
    query: &[u16],
    mut cursor: usize,
) -> Option<(u32, u32, usize)> {
    let folded = &general.folded;
    while cursor < folded.len() {
        let start = index_of(folded, query, cursor)?;
        let end = start + query.len();
        let map = field.map(general);
        if map.boundaries.get(start) && map.boundaries.get(end) {
            let location = map.starts.get(start);
            let original_end = map.ends.get(end - 1);
            cursor = end;
            while cursor < folded.len() && map.starts.get(cursor) < original_end {
                cursor += 1;
            }
            return Some((location, original_end - location, cursor));
        }
        cursor = start + 1;
    }
    None
}

// query는 접은 질의
// 빈 질의는 일치 없음
pub fn matches(field: &Field, query: &[u16]) -> bool {
    if query.is_empty() {
        return false;
    }
    match field {
        Field::Simple(bytes) => {
            encode_query(query).is_some_and(|needle| simple_index_of(bytes, &needle, 0).is_some())
        }
        Field::General(general) => general_first(general, general.prepared(), query, 0).is_some(),
    }
}

pub fn ranges(field: &Field, query: &[u16]) -> Vec<(u32, u32)> {
    let mut result = Vec::new();
    if query.is_empty() {
        return result;
    }
    match field {
        Field::Simple(bytes) => {
            let Some(needle) = encode_query(query) else {
                return result;
            };
            let mut cursor = 0;
            let mut location = 0;
            while let Some((start, skipped)) = simple_index_of(bytes, &needle, cursor) {
                location += skipped;
                result.push((location as u32, query.len() as u32));
                location += query.len();
                cursor = start + needle.len();
            }
        }
        Field::General(general) => {
            let prepared = general.prepared();
            let mut cursor = 0;
            while cursor < prepared.folded.len() {
                match general_first(general, prepared, query, cursor) {
                    Some((location, len, next)) => {
                        result.push((location, len));
                        cursor = next;
                    }
                    None => break,
                }
            }
        }
    }
    result
}

// 첫 일치가 40글자보다 뒤면 14글자 앞부터 발췌
pub fn excerpt_start(body: &[u16], location: u32) -> u32 {
    let letters = clusters(body);
    match letters
        .iter()
        .position(|letter| letter.index == location as usize)
    {
        Some(position) if 40 < position => letters[position - 14].index as u32,
        _ => 0,
    }
}
