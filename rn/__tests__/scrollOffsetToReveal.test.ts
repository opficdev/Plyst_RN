import { scrollOffsetToReveal } from '../src/screens/scrollOffsetToReveal';

test('행 전체가 이미 보이면 현재 오프셋을 유지한다', () => {
  expect(scrollOffsetToReveal(100, 300, 150, 250)).toBe(100);
  expect(scrollOffsetToReveal(100, 300, 100, 400)).toBe(100);
});

test('행 위쪽이 가려지면 행의 시작점까지 이동한다', () => {
  expect(scrollOffsetToReveal(100, 300, 50, 200)).toBe(50);
});

test('행 아래쪽이 가려지면 필요한 거리만 이동한다', () => {
  expect(scrollOffsetToReveal(100, 300, 350, 450)).toBe(150);
});

test('행이 뷰포트보다 크면 행의 시작점을 우선한다', () => {
  expect(scrollOffsetToReveal(100, 300, 150, 550)).toBe(150);
  expect(scrollOffsetToReveal(100, 300, 50, 450)).toBe(50);
});

test('계산 결과가 음수이면 0으로 제한한다', () => {
  expect(scrollOffsetToReveal(100, 300, -50, 100)).toBe(0);
  expect(scrollOffsetToReveal(-100, 300, -50, 250)).toBe(0);
  expect(scrollOffsetToReveal(-100, 300, 0, 100)).toBe(0);
});
