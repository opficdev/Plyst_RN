import { hangulWordBreak, wordJoiner } from '../../../src/Shared/UI/hangulWordBreak';

jest.mock('react-native', () => ({ Platform: { OS: 'android' } }));

test('공백이 아닌 글자와 붙은 한글 사이에 WORD JOINER를 넣는다', () => {
  expect(hangulWordBreak('복사 Plyst는')).toBe(`복${wordJoiner}사 Plyst${wordJoiner}는`);
});

test('조각의 끝이 다음 조각과 이어지면 끝에도 WORD JOINER를 넣는다', () => {
  expect(hangulWordBreak('회의록', 0, 2)).toBe(`회${wordJoiner}의${wordJoiner}`);
});

test('분해형 한글의 초성, 중성, 종성 사이에는 넣지 않고 글자 사이에만 넣는다', () => {
  const text = '\u1112\u1161\u11ab\u1100\u1173\u11af';
  expect(hangulWordBreak(text)).toBe(`\u1112\u1161\u11ab${wordJoiner}\u1100\u1173\u11af`);
});
