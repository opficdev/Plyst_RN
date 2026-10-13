import {
  clipCharacterCount,
  clipTextPrefix,
  clusters,
} from '../../src/Model/clipText';

test.each([
  ['👨‍👩‍👧‍👦', 1],
  ['🇰🇷', 1],
  ['e\u0301', 1],
])('문자소 경계를 보존한다: %s', (text, count) => {
  expect(clusters(text)).toHaveLength(count);
  expect(clipCharacterCount(text)).toBe(count);
});

test('Swift String.prefix와 같은 60개 문자소 접두어를 만든다', () => {
  const prefix = '👨‍👩‍👧‍👦🇰🇷e\u0301'.repeat(20);
  expect(clipCharacterCount(prefix + '끝')).toBe(61);
  expect(clipTextPrefix(prefix + '끝')).toBe(prefix);
});

test('문자 ZWJ 문자를 Swift와 같은 경계로 센다', () => {
  const text = 'a\u200db';
  const prefixSource = 'a'.repeat(59) + text;
  expect(clipCharacterCount(text)).toBe(2);
  expect(clipTextPrefix(prefixSource)).toBe('a'.repeat(60) + '\u200d');
});

test('제어 문자 뒤의 결합 문자를 별도 문자소로 센다', () => {
  const text = '\n\u0301';
  const prefixSource = 'a'.repeat(59) + text;
  expect(clipCharacterCount(text)).toBe(2);
  expect(clipTextPrefix(prefixSource)).toBe('a'.repeat(59) + '\n');
});

test('연속 ZWJ 뒤의 그림 문자를 별도 문자소로 센다', () => {
  expect(clipCharacterCount('👩\u200d\u200d👩')).toBe(2);
});

test('ZWNJ와 이모지 태그를 Swift와 같은 문자소로 센다', () => {
  const england = '🏴\u{E0067}\u{E0062}\u{E0065}\u{E006E}\u{E0067}\u{E007F}';
  expect(clipCharacterCount('a\u200c')).toBe(1);
  expect(clipCharacterCount(england)).toBe(1);
  expect(clipTextPrefix('a'.repeat(59) + england + '끝')).toBe(
    'a'.repeat(59) + england,
  );
});

test('문자소 제어 문자 뒤의 결합 문자를 분리한다', () => {
  expect(clipCharacterCount('x\u200b\u0301y')).toBe(4);
});

test('이미지 클립의 텍스트 파생 값은 비어 있다', () => {
  expect(clipCharacterCount(null)).toBe(0);
  expect(clipTextPrefix(null)).toBeNull();
});
