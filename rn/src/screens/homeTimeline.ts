export function nextHomeTimelineChange(
  createdAtList: readonly number[],
  now: number,
): number | null {
  if (createdAtList.length === 0) return null;
  const end = new Date(now);
  end.setHours(24, 0, 0, 0);
  let next = end.getTime();
  for (const createdAt of createdAtList) {
    // 상대 시각 문구와 방금 구간이 바뀌는 첫 시점만 비교합니다.
    for (const seconds of [0, 60, 120, 180, 240, 300]) {
      const transition = createdAt + seconds * 1000;
      if (now < transition) {
        if (transition < next) next = transition;
        break;
      }
    }
  }
  return next;
}
