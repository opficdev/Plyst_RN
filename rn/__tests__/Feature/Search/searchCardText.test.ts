import type { ClipRecord } from 'plyst-bridge';
import { searchCardText } from '../../../src/Feature/Search/searchCardText';
import { createSearchIndex } from '../../../src/Feature/Search/searchMatch';

const clip: ClipRecord = {
  id: 'text',
  text: 'Alpha alpha',
  name: 'ALPHA name',
  image: null,
  memo: null,
  isPinned: false,
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

test('늦은 일치는 앞에 말줄임표를 붙이고 UTF-16 범위를 옮긴다', () => {
  const text = '😀'.repeat(50) + 'target target';
  expect(
    searchCardText({ ...clip, text }, 'target', createSearchIndex()),
  ).toEqual({
    body: '…' + '😀'.repeat(14) + 'target target',
    nameHighlights: [],
    bodyHighlights: [
      { location: 29, length: 6 },
      { location: 36, length: 6 },
    ],
  });
});

test('분해된 한글도 글자 수로 발췌하고 범위는 UTF-16으로 옮긴다', () => {
  const prefix = '한'.normalize('NFD');
  const text = prefix.repeat(50) + 'target';
  const value = searchCardText(
    { ...clip, text },
    'target',
    createSearchIndex(),
  );
  expect(value.body).toBe('…' + prefix.repeat(14) + 'target');
  expect(value.bodyHighlights).toEqual([{ location: 43, length: 6 }]);
});

test('40번째 글자에서 시작하는 일치는 발췌하지 않는다', () => {
  const text = '가'.repeat(40) + 'target';
  expect(
    searchCardText({ ...clip, text }, 'target', createSearchIndex()).body,
  ).toBe(text);
});

test('이미지 이름 강조에는 대체 이름을 넣지 않는다', () => {
  const value = searchCardText(
    { ...clip, name: null, text: null },
    '이름',
    createSearchIndex(),
  );
  expect(value).toEqual({ body: '', nameHighlights: [], bodyHighlights: [] });
});

test('같은 검색의 강조 범위를 재사용하고 검색어 변경을 반영한다', () => {
  const index = createSearchIndex();
  const before = searchCardText(clip, 'alpha', index);
  const same = searchCardText(clip, 'alpha', index);
  expect(same.nameHighlights).toBe(before.nameHighlights);
  expect(same.bodyHighlights).toBe(before.bodyHighlights);
  expect(searchCardText(clip, 'name', index).nameHighlights).toEqual([
    { location: 6, length: 4 },
  ]);
});
