import {
  equivalent,
  normalizedMemo,
  normalizedName,
} from '../src/screens/clipDetailValues';

const whitespace =
  '\t\n\v\f\r\u0020\u0085\u00A0\u1680\u2000\u2001\u2002\u2003\u2004\u2005\u2006\u2007\u2008\u2009\u200A\u2028\u2029\u202F\u205F\u3000';

test.each<[string, string | null]>([
  ['  이름  ', '이름'],
  ['', null],
  [whitespace, null],
  [`${whitespace}이름${whitespace}`, '이름'],
  ['이 름\n본문', '이 름\n본문'],
  ['\uFEFF', '\uFEFF'],
  [`${whitespace}\uFEFF${whitespace}`, '\uFEFF'],
])('이름 %j을 정규화한다', (name, expected) => {
  expect(normalizedName({ name })).toBe(expected);
});

test.each<[string, string | null]>([
  ['', null],
  [whitespace, null],
  [`${whitespace}메모${whitespace}`, `${whitespace}메모${whitespace}`],
  ['\uFEFF', '\uFEFF'],
])('메모 %j의 공백 여부를 판정하고 내용을 보존한다', (memo, expected) => {
  expect(normalizedMemo({ memo })).toBe(expected);
});

test('정준 동등성을 적용하고 null과 빈 문자열을 구분한다', () => {
  expect(equivalent('é', 'e\u0301')).toBe(true);
  expect(equivalent(null, '')).toBe(false);
  expect(equivalent(null, null)).toBe(true);
});
