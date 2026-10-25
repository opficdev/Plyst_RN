export const homeHeaderSnapDuration = 0.22;

export type HomeScrollGeometry = {
  headerHeight: number;
  safeTop: number;
  insetTop: number;
  insetBottom: number;
  contentHeight: number;
  viewportHeight: number;
  sectionCount: number;
};
export type HomeHeaderPosition = {
  hidden: number;
  previousScrollY: number | null;
};

function boundedScrollY(offset: number, geometry: HomeScrollGeometry): number {
  const top = -geometry.insetTop;
  const bottom = Math.max(
    top,
    geometry.contentHeight - geometry.viewportHeight + geometry.insetBottom,
  );
  // 위아래 튕김을 제외한 실제 목록 범위로 제한함
  return Math.min(bottom, Math.max(top, offset));
}

function clampedHidden(
  hidden: number,
  scrollY: number,
  geometry: HomeScrollGeometry,
): number {
  if (geometry.sectionCount <= 0) return 0;
  // 헤더 높이와 상단 여백에서부터 이동한 거리까지만 숨김
  return Math.max(
    0,
    Math.min(geometry.headerHeight, hidden, scrollY + geometry.insetTop),
  );
}

export function updateHeaderHidden(
  position: HomeHeaderPosition,
  offset: number,
  geometry: HomeScrollGeometry,
  isDragging: boolean,
  isDecelerating: boolean,
  isUpdatingScrollGeometry = false,
): HomeHeaderPosition {
  // 배치나 스냅으로 위치를 조정하는 동안에는 스크롤 상태를 갱신하지 않음
  if (isUpdatingScrollGeometry) return position;
  const scrollY = boundedScrollY(offset, geometry);
  const previous = position.previousScrollY ?? scrollY;
  // 드래그나 감속 중에만 이전 위치와의 차이를 누적함
  const hidden =
    position.hidden + (isDragging || isDecelerating ? scrollY - previous : 0);
  return {
    hidden: clampedHidden(hidden, scrollY, geometry),
    previousScrollY: scrollY,
  };
}

export function snapHeaderTarget(
  hidden: number,
  offset: number,
  geometry: HomeScrollGeometry,
): { hidden: number; scrollY: number } | null {
  if (geometry.headerHeight <= 0) return null;
  const top = -geometry.insetTop;
  const scrollY = boundedScrollY(offset, geometry);
  // 헤더 아래쪽이 안전 영역 경계를 넘어갔을 때만 완전히 숨김
  const hides = geometry.headerHeight - geometry.safeTop < hidden;
  // 헤더 높이보다 적게 스크롤했다면 목록도 헤더 끝이나 맨 위로 이동함
  const targetY =
    scrollY - top < geometry.headerHeight
      ? boundedScrollY(hides ? top + geometry.headerHeight : top, geometry)
      : scrollY;
  const target = clampedHidden(
    hides ? geometry.headerHeight : 0,
    targetY,
    geometry,
  );
  if (target === hidden && targetY === scrollY) return null;
  return { hidden: target, scrollY: targetY };
}

export function reloadHeaderPosition(
  hidden: number,
  offset: number,
  geometry: HomeScrollGeometry,
) {
  // 빈 목록은 스크롤을 끄고 상단에 고정함
  // 헤더도 모두 드러냄
  const isScrollEnabled = 0 < geometry.sectionCount;
  const contentOffset = isScrollEnabled ? offset : -geometry.insetTop;
  const scrollY = boundedScrollY(contentOffset, geometry);
  return {
    isScrollEnabled,
    contentOffset,
    hidden: clampedHidden(hidden, scrollY, geometry),
    previousScrollY: scrollY,
  };
}

export function homeScrollToTop(insetTop: number) {
  // 필터가 실제로 바뀌면 화면에서 이 위치를 적용함
  // 최초 표시는 제외함
  return { hidden: 0, previousScrollY: -insetTop, contentOffset: -insetTop };
}
