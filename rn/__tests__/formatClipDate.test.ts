import { formatClipDate } from '../src/screens/formatClipDate';

test.each([
  [9, 5, '오전 9:05'],
  [15, 42, '오후 3:42'],
  [12, 0, '오후 12:00'],
  [0, 7, '오전 12:07'],
])('현지 시각 %i시 %i분을 표시한다', (hours, minutes, time) => {
  const date = new Date(2026, 0, 2, hours, minutes);
  expect(formatClipDate(date.getTime())).toBe(`2026년 1월 2일\n${time}`);
});

test('마지막 사용 시각이 없으면 빈 문자열이다', () => {
  expect(formatClipDate(null)).toBe('');
});
