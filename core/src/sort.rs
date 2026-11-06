use std::cmp::Ordering;

const ID_SIZE: usize = 16;

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
