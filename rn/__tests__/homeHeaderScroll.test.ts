import {
  homeHeaderSnapDuration,
  updateHeaderHidden,
  snapHeaderTarget,
  reloadHeaderPosition,
  homeScrollToTop,
} from '../src/screens/homeHeaderScroll';
import type { HomeScrollGeometry } from '../src/screens/homeHeaderScroll';

const geometry: HomeScrollGeometry = {
  headerHeight: 100,
  safeTop: 20,
  insetTop: 100,
  insetBottom: 30,
  contentHeight: 1000,
  viewportHeight: 500,
  sectionCount: 1,
};

test.each([
  [true, false],
  [false, true],
  [true, true],
])('드래그 %s 감속 %s에서 이동 차이를 누적한다', (dragging, decelerating) => {
  expect(
    updateHeaderHidden(
      { hidden: 10, previousScrollY: 0 },
      30,
      geometry,
      dragging,
      decelerating,
    ),
  ).toEqual({ hidden: 40, previousScrollY: 30 });
  expect(
    updateHeaderHidden(
      { hidden: 40, previousScrollY: 30 },
      10,
      geometry,
      dragging,
      decelerating,
    ),
  ).toEqual({ hidden: 20, previousScrollY: 10 });
});

test('프로그램 이동에서는 누적하지 않지만 현재 이동 거리로 제한한다', () => {
  expect(
    updateHeaderHidden(
      { hidden: 40, previousScrollY: 0 },
      30,
      geometry,
      false,
      false,
    ),
  ).toEqual({ hidden: 40, previousScrollY: 30 });
  expect(
    updateHeaderHidden(
      { hidden: 40, previousScrollY: 0 },
      -90,
      geometry,
      false,
      false,
    ),
  ).toEqual({ hidden: 10, previousScrollY: -90 });
});

test('이전 위치가 없으면 첫 이동량은 0이다', () => {
  expect(
    updateHeaderHidden(
      { hidden: 10, previousScrollY: null },
      30,
      geometry,
      true,
      false,
    ),
  ).toEqual({ hidden: 10, previousScrollY: 30 });
});

test('배치 갱신 중에는 이전 상태를 그대로 반환한다', () => {
  const position = { hidden: 10, previousScrollY: 0 };
  expect(updateHeaderHidden(position, 30, geometry, true, false, true)).toBe(
    position,
  );
});

test('위아래 튕김과 헤더 높이의 양쪽 경계를 제한한다', () => {
  expect(
    updateHeaderHidden(
      { hidden: 40, previousScrollY: 0 },
      -200,
      geometry,
      true,
      false,
    ),
  ).toEqual({ hidden: 0, previousScrollY: -100 });
  expect(
    updateHeaderHidden(
      { hidden: 40, previousScrollY: 0 },
      1000,
      geometry,
      true,
      false,
    ),
  ).toEqual({ hidden: 100, previousScrollY: 530 });
  expect(
    updateHeaderHidden(
      { hidden: 0, previousScrollY: 0 },
      -10,
      geometry,
      true,
      false,
    ).hidden,
  ).toBe(0);
});

test('짧은 목록의 하한은 상단 위치보다 작아지지 않는다', () => {
  expect(
    updateHeaderHidden(
      { hidden: 40, previousScrollY: 0 },
      1000,
      { ...geometry, contentHeight: 0 },
      true,
      false,
    ),
  ).toEqual({ hidden: 0, previousScrollY: -100 });
});

test('헤더를 숨길 때 상단 여백을 포함한 실제 이동 거리로 제한한다', () => {
  expect(
    updateHeaderHidden(
      { hidden: 90, previousScrollY: -90 },
      -80,
      { ...geometry, insetTop: 90 },
      true,
      false,
    ).hidden,
  ).toBe(10);
});

test('스냅 임계값과 같으면 보이고 초과하면 숨긴다', () => {
  expect(homeHeaderSnapDuration).toBe(0.22);
  expect(snapHeaderTarget(80, 50, geometry)).toEqual({
    hidden: 0,
    scrollY: 50,
  });
  expect(snapHeaderTarget(81, 50, geometry)).toEqual({
    hidden: 100,
    scrollY: 50,
  });
});

test('헤더 높이보다 적게 이동한 목록은 헤더와 함께 이동한다', () => {
  expect(snapHeaderTarget(80, -20, geometry)).toEqual({
    hidden: 0,
    scrollY: -100,
  });
  expect(snapHeaderTarget(81, -10, geometry)).toEqual({
    hidden: 100,
    scrollY: 0,
  });
  expect(snapHeaderTarget(80, 0, geometry)).toEqual({ hidden: 0, scrollY: 0 });
});

test('짧은 목록의 스냅도 아래쪽 경계를 넘지 않는다', () => {
  expect(
    snapHeaderTarget(81, -10, { ...geometry, contentHeight: 460 }),
  ).toEqual({ hidden: 90, scrollY: -10 });
});

test('헤더 높이가 없거나 이미 목표 위치이면 스냅하지 않는다', () => {
  expect(snapHeaderTarget(0, 0, { ...geometry, headerHeight: 0 })).toBeNull();
  expect(snapHeaderTarget(0, -100, geometry)).toBeNull();
  expect(snapHeaderTarget(100, 50, geometry)).toBeNull();
});

test('빈 목록은 상단으로 돌아가고 스크롤과 헤더 숨김을 해제한다', () => {
  const empty = { ...geometry, sectionCount: 0 };
  expect(reloadHeaderPosition(80, 50, empty)).toEqual({
    isScrollEnabled: false,
    contentOffset: -100,
    hidden: 0,
    previousScrollY: -100,
  });
  expect(
    updateHeaderHidden(
      { hidden: 80, previousScrollY: 0 },
      50,
      empty,
      true,
      false,
    ).hidden,
  ).toBe(0);
  expect(snapHeaderTarget(80, -20, empty)).toEqual({
    hidden: 0,
    scrollY: -100,
  });
});

test('내용 갱신은 실제 오프셋을 유지하고 기준 위치만 유효 범위로 제한한다', () => {
  expect(reloadHeaderPosition(80, 1000, geometry)).toEqual({
    isScrollEnabled: true,
    contentOffset: 1000,
    hidden: 80,
    previousScrollY: 530,
  });
});

test('필터 변경 시 적용할 상단 위치는 헤더를 모두 표시한다', () => {
  expect(homeScrollToTop(120)).toEqual({
    hidden: 0,
    previousScrollY: -120,
    contentOffset: -120,
  });
});
