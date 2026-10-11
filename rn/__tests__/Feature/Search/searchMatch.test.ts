import type { ClipRecord } from 'plyst-bridge';
import {
  clusters,
  createSearchIndex,
  normalizeSearchQuery,
  searchRanges,
} from '../../../src/Feature/Search/searchMatch';

// 실기기 Swift 원본의 23개 기대값을 고정합니다.
const cases = [
  {
    id: 'nfc_text_nfd_query',
    text: '한글 검색 테스트',
    query: '한',
    queryEmpty: false,
    ranges: [[0, 1]],
  },
  {
    id: 'nfd_text_nfc_query',
    text: '한글 검색',
    query: '한글',
    queryEmpty: false,
    ranges: [[0, 6]],
  },
  {
    id: 'nfd_partial_syllable',
    text: '한글',
    query: '하',
    queryEmpty: false,
    ranges: [],
  },
  {
    id: 'ascii_case',
    text: 'Clipboard Manager',
    query: 'CLIPBOARD',
    queryEmpty: false,
    ranges: [[0, 9]],
  },
  {
    id: 'german_sharp_s_upper',
    text: 'Straße',
    query: 'SS',
    queryEmpty: false,
    ranges: [[4, 1]],
  },
  {
    id: 'german_sharp_s_lower',
    text: 'Straße',
    query: 'strasse',
    queryEmpty: false,
    ranges: [[0, 6]],
  },
  {
    id: 'turkish_dotted_i',
    text: 'İstanbul',
    query: 'i',
    queryEmpty: false,
    ranges: [],
  },
  {
    id: 'greek_final_sigma',
    text: 'ΟΔΥΣΣΕΥΣ',
    query: 'οδυσσευς',
    queryEmpty: false,
    ranges: [[0, 8]],
  },
  {
    id: 'accent_nfd_text_ascii_query',
    text: 'café',
    query: 'cafe',
    queryEmpty: false,
    ranges: [],
  },
  {
    id: 'accent_nfc_text_nfd_query',
    text: 'café',
    query: 'café',
    queryEmpty: false,
    ranges: [[0, 4]],
  },
  {
    id: 'accent_distinguished',
    text: 'café',
    query: 'cafe',
    queryEmpty: false,
    ranges: [],
  },
  {
    id: 'fullwidth',
    text: 'ＡＢＣ',
    query: 'abc',
    queryEmpty: false,
    ranges: [],
  },
  {
    id: 'emoji_zwj_partial',
    text: '가족 👨‍👩‍👧 사진',
    query: '👩',
    queryEmpty: false,
    ranges: [],
  },
  {
    id: 'emoji_skin_tone',
    text: '👍🏽 좋아요',
    query: '👍',
    queryEmpty: false,
    ranges: [],
  },
  {
    id: 'flag_single_indicator',
    text: '🇰🇷 한국',
    query: '🇰',
    queryEmpty: false,
    ranges: [],
  },
  {
    id: 'overlap',
    text: 'aaaa',
    query: 'aa',
    queryEmpty: false,
    ranges: [
      [0, 2],
      [2, 2],
    ],
  },
  {
    id: 'whitespace_nel',
    text: 'abc',
    query: 'abc',
    queryEmpty: false,
    ranges: [[0, 3]],
  },
  {
    id: 'whitespace_bom',
    text: 'abc',
    query: '﻿abc',
    queryEmpty: false,
    ranges: [],
  },
  {
    id: 'whitespace_only',
    text: 'abc',
    query: ' \n\t',
    queryEmpty: true,
    ranges: [],
  },
  {
    id: 'whitespace_nbsp',
    text: 'abc',
    query: ' abc',
    queryEmpty: false,
    ranges: [[0, 3]],
  },
  {
    id: 'multiple_occurrences',
    text: 'Cat cat CAT',
    query: 'cat',
    queryEmpty: false,
    ranges: [
      [0, 3],
      [4, 3],
      [8, 3],
    ],
  },
  {
    id: 'compat_jamo',
    text: 'ㅎㅏㄴ글',
    query: 'ㅎ',
    queryEmpty: false,
    ranges: [[0, 1]],
  },
  {
    id: 'combining_query_only',
    text: 'e',
    query: 'é',
    queryEmpty: false,
    ranges: [],
  },
];

test.each(cases)('$id는 Swift 원본과 같다', (value) => {
  expect(normalizeSearchQuery(value.query) === '').toBe(value.queryEmpty);
  expect(
    searchRanges(value.text, value.query).map(({ location, length }) => [
      location,
      length,
    ]),
  ).toEqual(value.ranges);
});

test('양끝 공백과 개행을 제거하고 빈 입력을 거부한다', () => {
  expect(normalizeSearchQuery('  Swift \n')).toBe('Swift');
  expect(normalizeSearchQuery('')).toBe('');
  expect(normalizeSearchQuery(' \n\t ')).toBe('');
});

test('대소문자만 무시하고 악센트를 구분한다', () => {
  expect(searchRanges('Scan the QR code', 'qr')).toHaveLength(1);
  expect(searchRanges('qr', 'qr')).toHaveLength(1);
  expect(searchRanges('q r', 'qr')).toEqual([]);
  expect(searchRanges('Café', 'cafe')).toEqual([]);
});

test('겹치지 않는 모든 범위를 반환한다', () => {
  const text = 'aaaa AA a';
  expect(
    searchRanges(text, 'aa').map(({ location, length }) =>
      text.slice(location, location + length),
    ),
  ).toEqual(['aa', 'aa', 'AA']);
});

test('일치하지 않거나 원문이 비면 범위가 없다', () => {
  expect(searchRanges('abc', 'xyz')).toEqual([]);
  expect(searchRanges('', 'xyz')).toEqual([]);
});

test('한글 정준 등가의 범위는 원문을 가리킨다', () => {
  const decomposed = '한글'.normalize('NFD');
  const text = `앞 ${decomposed} 뒤`;
  const [range] = searchRanges(text, '한글');
  expect(text.slice(range.location, range.location + range.length)).toBe(
    decomposed,
  );
});

test('이모지와 결합 문자 중간에서는 일치하지 않는다', () => {
  const text = '👨‍👩‍👧 e\u0301x e';
  const boundaries = new Set(clusters(text).map(({ index }) => index));
  boundaries.add(text.length);
  const ranges = searchRanges(text, 'e');
  expect(ranges).toHaveLength(1);
  for (const range of ranges) {
    expect(boundaries.has(range.location)).toBe(true);
    expect(boundaries.has(range.location + range.length)).toBe(true);
  }
});

test.each([
  ['Cat cat CAT', 'cat'],
  ['한글 가나다 한글', '한글'],
  ['a\r\nb a\r\nb', 'a\r\nb'],
  ['첫째\n둘째\t셋째', '둘째'],
  ['ㄱㄴㄷ ABC', 'abc'],
  ['한글 café 한글', '한글'],
])('빠른 경로와 복잡 경로는 같은 범위를 반환한다: %s', (text, query) => {
  // 선두 이모지는 복잡 경로를 선택하게 하고 원문 오프셋만 2만큼 옮깁니다.
  const general = searchRanges(`😀${text}`, query).map((range) => ({
    ...range,
    location: range.location - 2,
  }));
  expect(searchRanges(text, query)).toEqual(general);
});

test('같은 id와 필드의 원문이 바뀌면 캐시를 무효화한다', () => {
  const index = createSearchIndex();
  expect(index.matches('a', 'body', 'Straße', 'ss')).toBe(true);
  expect(index.ranges('a', 'body', 'Straße', 'ss')).toEqual([
    { location: 4, length: 1 },
  ]);
  expect(index.matches('a', 'body', '다른 본문', 'ss')).toBe(false);
  expect(index.ranges('a', 'body', '다른 본문', 'ss')).toEqual([]);
});

const clip: ClipRecord = {
  id: 'a',
  text: 'Straße 한글'.normalize('NFD'),
  name: 'Café',
  image: null,
  memo: null,
  isPinned: false,
  isWebLink: false,
  characterCount: 9,
  textPrefix: 'Straße 한글',
  createdAt: 0,
  lastUsedAt: null,
};

test('유휴 사전 구축 전후의 결과가 같고 목록 제거 뒤 다시 만들 수 있다', () => {
  jest.useFakeTimers();
  try {
    const index = createSearchIndex();
    const before = index.ranges(clip.id, 'body', clip.text!, '한글');
    index.prebuild([clip]);
    jest.runAllTimers();
    expect(index.ranges(clip.id, 'body', clip.text!, '한글')).toEqual(before);
    index.retain([]);
    expect(index.ranges(clip.id, 'body', clip.text!, '한글')).not.toBe(before);
    expect(index.ranges(clip.id, 'body', clip.text!, '한글')).toEqual(before);
    index.dispose();
  } finally {
    jest.useRealTimers();
  }
});

test('사전 구축은 재조회와 해제 시 취소한다', () => {
  jest.useFakeTimers();
  try {
    const index = createSearchIndex();
    index.prebuild([clip]);
    expect(jest.getTimerCount()).toBe(1);
    index.cancelPrebuild();
    expect(jest.getTimerCount()).toBe(0);
    index.prebuild([clip]);
    index.dispose();
    expect(jest.getTimerCount()).toBe(0);
  } finally {
    jest.useRealTimers();
  }
});
