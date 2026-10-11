import { labelTruncation } from '../../../../src/Shared/UI/ClipCard/labelTruncation';

test('두 번째 문단 끝의 줄바꿈을 제외한 위치를 반환한다', () => {
  const text = 'a\nb\nc';
  const cut = labelTruncation(text, [{ text: 'a\n' }, { text: 'b\n' }], 2);
  expect(cut).toBe(3);
  expect(text.slice(0, cut!) + '…').toBe('a\nb…');
});

test('CRLF 줄바꿈을 통째로 제외한다', () => {
  const text = 'a\r\nb\r\nc';
  const cut = labelTruncation(text, [{ text: 'a\r\n' }, { text: 'b\r\n' }], 2);
  expect(cut).toBe(4);
  expect(text.slice(0, cut!) + '…').toBe('a\r\nb…');
});

test('마지막으로 보이는 빈 문단의 줄바꿈만 제외한다', () => {
  const text = 'a\n\nb';
  const cut = labelTruncation(text, [{ text: 'a\n' }, { text: '\n' }], 2);
  expect(cut).toBe(2);
  expect(text.slice(0, cut!) + '…').toBe('a\n…');
});

test.each(['\n', '\r', '\u2028', '\u2029'])(
  '%j 줄바꿈을 처리한다',
  (newline) => {
    expect(
      labelTruncation(
        `a${newline}b${newline}c`,
        [{ text: `a${newline}` }, { text: `b${newline}` }],
        2,
      ),
    ).toBe(3);
  },
);

test('끝 줄바꿈까지 전체 본문이 보이면 변환하지 않는다', () => {
  expect(
    labelTruncation('a\nb\n', [{ text: 'a\n' }, { text: 'b\n' }], 2),
  ).toBeNull();
});

test.each([1, 3])('실제 줄 수가 제한 %i와 다르면 변환하지 않는다', (limit) => {
  expect(
    labelTruncation('a\nb\nc', [{ text: 'a\n' }, { text: 'b\n' }], limit),
  ).toBeNull();
});

test.each([0, -1])('줄 수 제한이 %i이면 변환하지 않는다', (limit) => {
  expect(labelTruncation('a\nb', [{ text: 'a\n' }], limit)).toBeNull();
});

test('레이아웃에 줄이 없으면 변환하지 않는다', () => {
  expect(labelTruncation('a\nb', [], 1)).toBeNull();
  expect(labelTruncation('', [], 0)).toBeNull();
});

test('마지막 줄이 줄바꿈으로 끝나지 않으면 변환하지 않는다', () => {
  expect(
    labelTruncation('a\nb\nc', [{ text: 'a\n' }, { text: 'b' }], 2),
  ).toBeNull();
  expect(labelTruncation('abc', [{ text: 'ab' }], 1)).toBeNull();
});

test('보이는 길이가 원문보다 길면 변환하지 않는다', () => {
  expect(labelTruncation('a', [{ text: 'a\n' }], 1)).toBeNull();
});

test('첫 줄이 빈 문단이면 위치 0을 반환한다', () => {
  expect(labelTruncation('\nb', [{ text: '\n' }], 1)).toBe(0);
});

test('보조 평면 문자를 UTF-16 길이로 계산한다', () => {
  expect(
    labelTruncation('😀\nb\nc', [{ text: '😀\n' }, { text: 'b\n' }], 2),
  ).toBe(4);
});
