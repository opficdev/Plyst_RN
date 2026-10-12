import { clipSectionKind } from '../../../src/Feature/ClipGrid/section';

const now = new Date(2026, 9, 11, 12).getTime();

test.each<[number, string]>([
  [now + 1000, 'recent'],
  [now - 299_999, 'recent'],
  [now - 300_000, 'today'],
  [new Date(2026, 9, 11).getTime(), 'today'],
  [new Date(2026, 9, 11).getTime() - 1, 'yesterday'],
  [new Date(2026, 9, 10).getTime(), 'yesterday'],
  [new Date(2026, 9, 10).getTime() - 1, 'earlier'],
])('%s의 분류는 %s이다', (createdAt, expected) => {
  expect(clipSectionKind(createdAt, now)).toBe(expected);
});

test('자정을 넘어도 최근 5분을 먼저 판별하며 경계는 제외한다', () => {
  const midnight = new Date(2026, 9, 11, 0, 2).getTime();
  expect(clipSectionKind(midnight - 180_000, midnight)).toBe('recent');
  expect(clipSectionKind(midnight - 300_000, midnight)).toBe('yesterday');
});
