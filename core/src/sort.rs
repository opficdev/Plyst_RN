use std::cmp::Ordering;

const TIME_SIZE: usize = 8;
const ID_SIZE: usize = 16;

pub(crate) fn input_order(count: usize) -> Vec<u8> {
    (0..count as u32).flat_map(u32::to_le_bytes).collect()
}

// 입력 시각과 결과는 원소별 직렬화를 피하려고 리틀 엔디언 원시 바이트로 전달
pub(crate) fn encoded_order(created_at: &[u8], ids: &[u8]) -> Vec<u8> {
    let count = created_at.len() / TIME_SIZE;
    if !created_at.len().is_multiple_of(TIME_SIZE) || ids.len() != count * ID_SIZE {
        return input_order(count);
    }
    let times: Vec<f64> = created_at
        .as_chunks::<TIME_SIZE>()
        .0
        .iter()
        .map(|bytes| f64::from_le_bytes(*bytes))
        .collect();
    order(&times, ids)
        .into_iter()
        .flat_map(u32::to_le_bytes)
        .collect()
}

// 생성 시각의 내림차순으로 정렬
// 생성 시각이 같으면 식별자의 오름차순으로 순서를 결정
// 16바이트 비교와 대문자 UUID 문자열 비교의 결과는 같음
// +0.0으로 -0.0과 0.0을 같은 값으로 맞춤
pub(crate) fn order(created_at: &[f64], ids: &[u8]) -> Vec<u32> {
    let times: Vec<f64> = created_at.iter().map(|time| time + 0.0).collect();
    let id = |index: u32| &ids[index as usize * ID_SIZE..][..ID_SIZE];
    let mut order: Vec<u32> = (0..times.len() as u32).collect();
    order.sort_by(
        |&lhs, &rhs| match times[rhs as usize].total_cmp(&times[lhs as usize]) {
            Ordering::Equal => id(lhs).cmp(id(rhs)),
            ordering => ordering,
        },
    );
    order
}
