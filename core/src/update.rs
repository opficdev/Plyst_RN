use crate::ClipIdentity;

// 새로 고정하면 요청 시각을 기록
// 이미 고정되어 있으면 기존 고정 시각을 유지하고 해제하면 제거
pub(crate) fn pinned_at(current: Option<f64>, is_pinned: bool, requested_at: f64) -> Option<f64> {
    is_pinned.then(|| current.unwrap_or(requested_at))
}

// 식별자와 원본, 생성 시각이 같은 클립에만 사용 시각을 적용
pub(crate) fn usage_applies(expected: &ClipIdentity, current: &ClipIdentity) -> bool {
    expected == current
}
