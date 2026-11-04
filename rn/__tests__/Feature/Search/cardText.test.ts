import { searchCoreCardText } from 'plyst-search';
import type { ClipRecord } from '../../../src/Model/clipRecord';
import { searchCardText } from '../../../src/Feature/Search/cardText';
import { createSearchIndex } from '../../../src/Feature/Search/match';

const clip: ClipRecord = {
  id: 'text',
  text: 'Alpha alpha',
  name: 'ALPHA name',
  image: null,
  memo: null,
  pinnedAt: null,
  isWebLink: false,
  characterCount: 11,
  textPrefix: 'Alpha alpha',
  createdAt: 0,
  lastUsedAt: null,
};

test('이름과 본문의 모든 강조 범위를 구분한다', () => {
  expect(searchCardText(clip, 'alpha', createSearchIndex())).toEqual({
    body: 'Alpha alpha',
    nameHighlights: [{ location: 0, length: 5 }],
    bodyHighlights: [
      { location: 0, length: 5 },
      { location: 6, length: 5 },
    ],
  });
});

test('일치가 없으면 본문을 그대로 반환한다', () => {
  expect(searchCardText(clip, '다른', createSearchIndex())).toEqual({
    body: clip.text,
    nameHighlights: [],
    bodyHighlights: [],
  });
});

test('발췌 시작 위치부터 말줄임표를 붙이고 UTF-16 범위를 옮긴다', () => {
  const text = '😀'.repeat(50) + 'target target';
  jest.mocked(searchCoreCardText).mockReturnValueOnce({ nameRanges: [], bodyRanges: [100, 6, 107, 6], excerptStart: 72 });
  expect(searchCardText({ ...clip, text }, 'target', createSearchIndex())).toEqual({
    body: '…' + '😀'.repeat(14) + 'target target',
    nameHighlights: [],
    bodyHighlights: [
      { location: 29, length: 6 },
      { location: 36, length: 6 },
    ],
  });
});

test('발췌 시작 위치가 0이면 본문을 그대로 쓴다', () => {
  const text = '가'.repeat(40) + 'target';
  expect(searchCardText({ ...clip, text }, 'target', createSearchIndex()).body).toBe(text);
});

test('이미지 이름 강조에는 대체 이름을 넣지 않는다', () => {
  const value = searchCardText({ ...clip, name: null, text: null }, '이름', createSearchIndex());
  expect(value).toEqual({ body: '', nameHighlights: [], bodyHighlights: [] });
});

test('같은 검색의 강조 범위를 재사용하고 검색어 변경을 반영한다', () => {
  const index = createSearchIndex();
  const before = searchCardText(clip, 'alpha', index);
  const same = searchCardText(clip, 'alpha', index);
  expect(same.nameHighlights).toBe(before.nameHighlights);
  expect(same.bodyHighlights).toBe(before.bodyHighlights);
  expect(searchCardText(clip, 'name', index).nameHighlights).toEqual([{ location: 6, length: 4 }]);
});
