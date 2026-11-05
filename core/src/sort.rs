use std::cmp::Ordering;

const ID_SIZE: usize = 16;

// 생성 시각의 내림차순으로 정렬
// 생성 시각이 같으면 식별자의 오름차순으로 순서를 결정
// 16바이트 비교와 대문자 UUID 문자열 비교의 결과는 같음
// +0.0으로 -0.0과 0.0을 같은 값으로 맞춤
pub(crate) fn order(created_at: &[f64], ids: &[u8]) -> Vec<u32> {
    let mut order: Vec<u32> = (0..created_at.len() as u32).collect();
    if ids.len() != created_at.len() * ID_SIZE {
        return order;
    }
    let id = |index: u32| &ids[index as usize * ID_SIZE..][..ID_SIZE];
    let time = |index: u32| created_at[index as usize] + 0.0;
    order.sort_by(|&lhs, &rhs| match time(rhs).total_cmp(&time(lhs)) {
        Ordering::Equal => id(lhs).cmp(id(rhs)),
        ordering => ordering,
    });
    order
}
