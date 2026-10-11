import { nextClipTimelineChange } from '../../../src/Feature/ClipGrid/clipTimeline';

const createdAt = new Date(2026, 9, 10, 12).getTime();

test('빈 목록은 타이머를 예약하지 않는다', () => {
  expect(nextClipTimelineChange([], createdAt)).toBeNull();
});

test.each([
  [-1000, 0],
  [0, 60000],
  [59000, 60000],
  [60000, 120000],
  [120000, 180000],
  [180000, 240000],
  [240000, 300000],
  [299000, 300000],
])('생성 후 %i밀리초에는 다음 경계 %i를 예약한다', (age, next) => {
  expect(nextClipTimelineChange([createdAt], createdAt + age)).toBe(
    createdAt + next,
  );
});

test('5분이 지난 항목만 있으면 다음 현지 자정을 예약한다', () => {
  expect(nextClipTimelineChange([createdAt], createdAt + 300000)).toBe(
    new Date(2026, 9, 11).getTime(),
  );
});

test('순서에 관계없이 모든 항목 중 가장 빠른 경계를 선택한다', () => {
  const dates = [createdAt - 59000, createdAt - 300000, createdAt + 500];
  expect(nextClipTimelineChange(dates, createdAt)).toBe(createdAt + 500);
  expect(nextClipTimelineChange([...dates].reverse(), createdAt)).toBe(
    createdAt + 500,
  );
});

test('상대 시각 경계보다 자정이 빠르면 자정을 선택한다', () => {
  const midnight = new Date(2026, 9, 11).getTime();
  expect(nextClipTimelineChange([midnight - 10000], midnight - 1000)).toBe(
    midnight,
  );
  expect(nextClipTimelineChange([midnight - 10000], midnight)).toBe(
    midnight + 50000,
  );
});

test.each([
  [2026, 2, 8],
  [2026, 10, 1],
])('현지 날짜 %i/%i/%i의 다음 날 시작을 사용한다', (year, month, day) => {
  const now = new Date(year, month, day, 0).getTime();
  expect(nextClipTimelineChange([now - 300000], now)).toBe(
    new Date(year, month, day + 1).getTime(),
  );
});
