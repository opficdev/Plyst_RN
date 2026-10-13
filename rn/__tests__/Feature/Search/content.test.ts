import type { ClipRecord } from '../../../src/Model/clipRecord';
import type { ClipFilter } from '../../../src/Feature/ClipGrid/filter';
import {
  createSearchTimeTexts,
  makeSearchContent,
  searchEmptyStrings,
  searchExcerptStart,
  searchHeaderTitle,
  searchMode,
  searchRecentDisplay,
} from '../../../src/Feature/Search/content';
import { createSearchIndex } from '../../../src/Feature/Search/match';
import { searchCardText } from '../../../src/Feature/Search/cardText';

const now = new Date(2026, 9, 11, 12).getTime();
const text: ClipRecord = {
  id: 'text',
  text: 'report text',
  name: null,
  image: null,
  memo: null,
  pinnedAt: null,
  isWebLink: false,
  characterCount: 11,
  textPrefix: 'report text',
  createdAt: now,
  lastUsedAt: null,
};
const image: ClipRecord = {
  ...text,
  id: 'image',
  text: null,
  textPrefix: null,
  name: 'report image',
  image: {
    byteCount: 100,
    contentType: 'public.png',
    pixelWidth: 10,
    pixelHeight: 10,
  },
};
const pinned = { ...text, id: 'pinned', pinnedAt: 1000 };
function content(
  clips: ClipRecord[],
  query: string,
  filter: ClipFilter = 'all',
) {
  return makeSearchContent(
    clips,
    query,
    filter,
    now,
    createSearchIndex(),
    createSearchTimeTexts(),
  );
}

test('공백 검색어에는 결과가 없다', () => {
  expect(content([text], ' \n\t ').results).toEqual([]);
});

test('이름과 본문을 대소문자 구분 없이 검색한다', () => {
  const body = { ...text, text: 'Scan the QR code' };
  const named = { ...text, id: 'named', name: 'qr 메모', text: '무관한 본문' };
  expect(content([body, named, text], 'qr').results).toEqual([body, named]);
});

test('일치 범위가 원래 이름과 본문을 가리킨다', () => {
  const clip = { ...text, text: 'Alpha alpha', name: 'ALPHA name' };
  const display = searchCardText(clip, 'alpha', createSearchIndex());
  expect(display.nameHighlights).toEqual([{ location: 0, length: 5 }]);
  expect(display.bodyHighlights).toEqual([
    { location: 0, length: 5 },
    { location: 6, length: 5 },
  ]);
});

test('이미지는 이름으로 찾고 대체 문구로 찾지 않는다', () => {
  const unnamed = { ...image, id: 'unnamed', name: null };
  expect(content([image, unnamed], 'REPORT').results).toEqual([image]);
  expect(content([unnamed], '이름 없는').results).toEqual([]);
});

test('저장 시각은 이미지만 검색하고 날짜 표기도 검색한다', () => {
  const createdAt = new Date(2026, 9, 10, 12).getTime();
  const saved = { ...image, createdAt };
  const plain = { ...text, createdAt };
  expect(content([saved, plain], '어제').results).toEqual([saved]);
  const date = new Intl.DateTimeFormat(undefined, {
    dateStyle: 'medium',
  }).format(new Date(createdAt));
  expect(content([saved, plain], date).results).toEqual([saved]);
});

test.each<[ClipFilter, ClipRecord[], number, number]>([
  ['all', [text, pinned, image], 2, 1],
  ['text', [text, pinned], 2, 0],
  ['image', [image], 0, 1],
  ['pinned', [pinned], 1, 0],
])('%s 필터를 먼저 적용한 결과와 개수를 반환한다', (filter, results, a, b) => {
  expect(content([text, pinned, image], 'report', filter)).toMatchObject({
    results,
    textCount: a,
    imageCount: b,
  });
});

test('결과는 입력 순서를 유지한다', () => {
  const clips = [image, pinned, text];
  expect(content(clips, 'report').results).toEqual(clips);
});

test('40글자를 넘은 첫 일치에서 14글자 앞부터 발췌한다', () => {
  expect(searchExcerptStart('가'.repeat(50) + 'target', 50)).toBe(36);
  expect(searchExcerptStart('target' + '가'.repeat(50), 0)).toBe(0);
  expect(searchExcerptStart('가'.repeat(40) + 'target', 40)).toBe(0);
});

test('종류가 섞인 결과에만 종류별 개수를 표시한다', () => {
  expect(searchHeaderTitle(content([text, image], 'report'))).toBe(
    '결과 2개 · 텍스트 1 · 이미지 1',
  );
  expect(searchHeaderTitle(content([text], 'report'))).toBe('결과 1개');
  expect(searchHeaderTitle(content([], 'report'))).toBe('결과 0개');
});

test('조회 단계와 전체 클립에 따라 화면 모드를 결정한다', () => {
  const empty = content([], 'report');
  expect(searchMode(content([], ''), 'failed', [])).toBe('recent');
  expect(searchMode(empty, 'loading', [])).toBe('results');
  expect(searchMode(empty, 'loaded', [])).toBe('empty');
  expect(searchMode(empty, 'failed', [])).toBe('failed');
  expect(searchMode(empty, 'failed', [text])).toBe('empty');
  expect(searchMode(content([text], 'report'), 'failed', [text])).toBe(
    'results',
  );
});

test('빈 결과와 조회 실패 문구는 원본과 같다', () => {
  expect(searchEmptyStrings('단어', 'all', false)).toEqual({
    title: '‘단어’ 결과 없음',
    message: '이미지는 이름과 저장 시각으로만 찾을 수 있어요.',
  });
  for (const filter of ['text', 'image', 'pinned'] as const)
    expect(searchEmptyStrings('단어', filter, false).message).toBe(
      '필터를 ‘전체’로 바꾸거나 다른 단어로 검색해 보세요.',
    );
  expect(searchEmptyStrings('단어', 'all', true)).toEqual({
    title: '기록을 불러오지 못했습니다',
    message: '앱을 다시 열어 기록을 확인해 주세요',
  });
});

test('최근 검색어 초기 상태는 비어 있고 실패 상태에는 지우기를 남긴다', () => {
  expect(searchRecentDisplay('initial', [])).toEqual({
    terms: [],
    message: null,
    isClearVisible: false,
  });
  expect(searchRecentDisplay('loaded', [])).toEqual({
    terms: [],
    message: '최근 검색어가 없어요.',
    isClearVisible: false,
  });
  expect(searchRecentDisplay('loaded', ['단어'])).toEqual({
    terms: ['단어'],
    message: null,
    isClearVisible: true,
  });
  expect(searchRecentDisplay('failed', ['이전'])).toEqual({
    terms: [],
    message: '최근 검색어를 불러오지 못했어요.',
    isClearVisible: true,
  });
});

test('시각 문자열은 동일 시각에 재사용하고 시각 또는 원문 변경 시 갱신한다', () => {
  const times = createSearchTimeTexts();
  const before = times.texts(image, now);
  expect(times.texts(image, now)).toBe(before);
  expect(times.texts(image, now + 60_000)).not.toBe(before);
  const changed = { ...image, createdAt: now - 86_400_000 };
  expect(times.texts(changed, now)[0]).toContain('어제');
  times.retain([]);
  expect(times.texts(image, now)).not.toBe(before);
});

test('고정 필터의 검색 결과도 고정 시각과 무관하게 입력 순서를 유지한다', () => {
  const first = { ...text, id: 'first', pinnedAt: 1 };
  const recent = { ...text, id: 'recent', pinnedAt: 2 };
  expect(content([first, recent], 'report', 'pinned').results).toEqual([
    first,
    recent,
  ]);
});
