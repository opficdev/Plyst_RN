import { formatHomeCardTime } from '../src/screens/homeCardFormat';

const now = new Date(2026, 9, 10, 12).getTime();
const shortTime = (date: number) =>
  new Intl.DateTimeFormat(undefined, { timeStyle: 'short' }).format(date);
const dateTime = (date: number) =>
  new Intl.DateTimeFormat(undefined, {
    dateStyle: 'medium',
    timeStyle: 'short',
  }).format(date);

test.each([
  [0, '지금'],
  [59000, '지금'],
  [59999, '지금'],
  [60000, '1분 전'],
  [119999, '1분 전'],
  [120000, '2분 전'],
  [180000, '3분 전'],
  [240000, '4분 전'],
  [299000, '4분 전'],
  [299999, '4분 전'],
])('경과 시간 %i밀리초의 상대 시각을 표시한다', (age, expected) => {
  expect(formatHomeCardTime(now - age, now)).toBe(expected);
});

test('5분부터는 짧은 시각을 표시한다', () => {
  expect(formatHomeCardTime(now - 300000, now)).toBe(shortTime(now - 300000));
});

test('음수 경과 시간에는 상대 시각을 표시하지 않는다', () => {
  expect(formatHomeCardTime(now + 1000, now)).toBe(shortTime(now + 1000));
  const tomorrow = new Date(2026, 9, 11, 12).getTime();
  expect(formatHomeCardTime(tomorrow, now)).toBe(dateTime(tomorrow));
});

test('오늘과 어제는 시각만 표시하고 이전 날짜는 날짜를 함께 표시한다', () => {
  const today = new Date(2026, 9, 10).getTime();
  const yesterday = new Date(2026, 9, 9).getTime();
  for (const date of [today, today - 1, yesterday]) {
    expect(formatHomeCardTime(date, now)).toBe(shortTime(date));
  }
  expect(formatHomeCardTime(yesterday - 1, now)).toBe(dateTime(yesterday - 1));
});

test('자정을 지나도 상대 시각 분기가 먼저 적용된다', () => {
  const midnight = new Date(2026, 9, 10).getTime();
  expect(formatHomeCardTime(midnight - 59000, midnight)).toBe('지금');
  expect(formatHomeCardTime(midnight - 299000, midnight)).toBe('4분 전');
});
