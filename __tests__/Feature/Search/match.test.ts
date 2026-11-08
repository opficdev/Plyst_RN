import { cancelSearchCorePrebuild, createSearchCore, filterSearchCore, freeSearchCore, prebuildSearchCore, searchCoreCardText, syncSearchCore } from 'plyst-search';
import type { ClipRecord } from '../../../src/Model/clipRecord';
import { createSearchIndex, normalizeSearchQuery } from '../../../src/Feature/Search/match';

const text: ClipRecord = {
  id: 'text',
  text: 'Alpha body',
  name: 'Note',
  image: null,
  memo: null,
  pinnedAt: null,
  isWebLink: false,
  characterCount: 10,
  textPrefix: 'Alpha body',
  createdAt: 0,
  lastUsedAt: null,
};
const image: ClipRecord = {
  ...text,
  id: 'image',
  text: null,
  name: null,
  image: { byteCount: 1, contentType: 'image/png', pixelWidth: 1, pixelHeight: 1 } as ClipRecord['image'],
};
const times = () => ['오늘 오전 10:00', '2026. 11. 4.'];

beforeEach(() => {
  jest.clearAllMocks();
});

test('양끝 공백과 개행을 제거하고 빈 입력을 거부한다', () => {
  expect(normalizeSearchQuery('  Swift \n')).toBe('Swift');
  expect(normalizeSearchQuery('')).toBe('');
  expect(normalizeSearchQuery(' \n\t ')).toBe('');
});

test('prebuild는 텍스트 클립의 이름과 본문과 이미지 클립의 이름을 보낸 뒤 작업을 시작한다', () => {
  const index = createSearchIndex();
  index.prebuild([text, image]);
  expect(createSearchCore).toHaveBeenCalledTimes(1);
  expect(syncSearchCore).toHaveBeenCalledWith(expect.any(Number), ['text', 'image'], [0, 0, 1], [0, 1, 0], ['Note', 'Alpha body', '']);
  expect(prebuildSearchCore).toHaveBeenCalledTimes(1);
  index.dispose();
});

test('같은 clips는 다시 보내지 않고 바뀐 필드만 보낸다', () => {
  const index = createSearchIndex();
  const clips = [text, image];
  index.prebuild(clips);
  index.prebuild(clips);
  expect(syncSearchCore).toHaveBeenCalledTimes(1);
  index.prebuild([{ ...text, name: '새 이름' }, image]);
  expect(syncSearchCore).toHaveBeenCalledTimes(2);
  expect(syncSearchCore).toHaveBeenLastCalledWith(expect.any(Number), ['text', 'image'], [0], [0], ['새 이름']);
  index.dispose();
});

test('시간 문자열은 검색할 때 이미지 클립만 보내고 같은 시각이면 다시 보내지 않는다', () => {
  const index = createSearchIndex();
  const clips = [text, image];
  index.prebuild(clips);
  index.filter(clips, '오늘', 1, times);
  expect(syncSearchCore).toHaveBeenLastCalledWith(expect.any(Number), ['text', 'image'], [1, 1], [2, 3], times());
  expect(syncSearchCore).toHaveBeenCalledTimes(2);
  index.filter(clips, '오전', 1, times);
  expect(syncSearchCore).toHaveBeenCalledTimes(2);
  index.filter(clips, '오전', 2, times);
  expect(syncSearchCore).toHaveBeenCalledTimes(2);
  index.filter(clips, '오전', 3, () => ['어제 오전 10:00', '2026. 11. 4.']);
  expect(syncSearchCore).toHaveBeenLastCalledWith(expect.any(Number), ['text', 'image'], [1], [2], ['어제 오전 10:00']);
  index.dispose();
});

test('filter는 일치한 위치를 입력 순서의 클립으로 바꾼다', () => {
  const index = createSearchIndex();
  const second = { ...text, id: 'second' };
  expect(index.filter([text, image, second], 'alpha', 1, times)).toEqual([text, second]);
  index.dispose();
});

test('빈 검색어는 네이티브를 부르지 않는다', () => {
  const index = createSearchIndex();
  expect(index.filter([text], ' \n', 1, times)).toEqual([]);
  expect(index.cardText(text, ' ')).toEqual({ nameRanges: [], bodyRanges: [], excerptStart: 0 });
  expect(filterSearchCore).not.toHaveBeenCalled();
  expect(searchCoreCardText).not.toHaveBeenCalled();
});

test('cardText는 마지막으로 보낸 값과 같을 때만 저장된 필드를 쓰게 한다', () => {
  const index = createSearchIndex();
  index.prebuild([text]);
  index.cardText(text, 'alpha');
  expect(searchCoreCardText).toHaveBeenLastCalledWith(expect.any(Number), 'text', 'Note', 'Alpha body', 'alpha', true);
  index.cardText({ ...text, text: 'Alpha 다른 본문' }, 'alpha');
  expect(searchCoreCardText).toHaveBeenLastCalledWith(expect.any(Number), 'text', 'Note', 'Alpha 다른 본문', 'alpha', false);
  index.dispose();
});

test('이미지 클립은 본문 없이도 저장된 이름을 쓴다', () => {
  const index = createSearchIndex();
  index.prebuild([image]);
  index.cardText(image, 'alpha');
  expect(searchCoreCardText).toHaveBeenLastCalledWith(expect.any(Number), 'image', '', '', 'alpha', true);
  index.dispose();
});

test('같은 이름, 본문, 접은 질의면 이전 결과를 그대로 돌려준다', () => {
  const index = createSearchIndex();
  const before = index.cardText(text, 'alpha');
  expect(index.cardText(text, ' ALPHA ')).toBe(before);
  expect(searchCoreCardText).toHaveBeenCalledTimes(1);
  expect(index.cardText(text, 'body')).not.toBe(before);
  index.dispose();
});

test('목록에서 빠진 클립의 범위 캐시를 지운다', () => {
  const index = createSearchIndex();
  index.prebuild([text]);
  index.cardText(text, 'alpha');
  index.prebuild([]);
  index.cardText(text, 'alpha');
  expect(searchCoreCardText).toHaveBeenCalledTimes(2);
  index.dispose();
});

test('sync 실패는 핸들을 버리고 다음 호출이 새 핸들에 전체를 보낸다', () => {
  const index = createSearchIndex();
  index.prebuild([text]);
  jest.mocked(syncSearchCore).mockReturnValueOnce(false);
  expect(index.filter([text, image], 'alpha', 1, times)).toEqual([]);
  expect(freeSearchCore).toHaveBeenCalledTimes(1);
  expect(index.filter([text, image], 'alpha', 1, times)).toEqual([text]);
  expect(createSearchCore).toHaveBeenCalledTimes(2);
  expect(jest.mocked(syncSearchCore).mock.lastCall?.[4]).toEqual(['Note', 'Alpha body', '', ...times()]);
  index.dispose();
});

test.each([
  ['filter', (index: ReturnType<typeof createSearchIndex>) => index.filter([text], 'alpha', 1, times), [], filterSearchCore],
  ['cardText', (index: ReturnType<typeof createSearchIndex>) => index.cardText(text, 'alpha'), { nameRanges: [], bodyRanges: [], excerptStart: 0 }, searchCoreCardText],
])('%s 실패는 빈 결과를 돌려주고 핸들을 버린다', (_, call, empty, native) => {
  const index = createSearchIndex();
  index.prebuild([text]);
  jest.mocked(native as typeof filterSearchCore).mockReturnValueOnce(null);
  expect(call(index)).toEqual(empty);
  expect(freeSearchCore).toHaveBeenCalledTimes(1);
  index.prebuild([text]);
  expect(createSearchCore).toHaveBeenCalledTimes(2);
  index.dispose();
});

test('prebuild 실패는 핸들을 버린다', () => {
  const index = createSearchIndex();
  jest.mocked(prebuildSearchCore).mockReturnValueOnce(false);
  index.prebuild([text]);
  expect(freeSearchCore).toHaveBeenCalledTimes(1);
});

test('핸들을 만들지 못하면 빈 결과를 돌려준다', () => {
  const index = createSearchIndex();
  jest.mocked(createSearchCore).mockReturnValueOnce(0);
  expect(index.filter([text], 'alpha', 1, times)).toEqual([]);
  expect(syncSearchCore).not.toHaveBeenCalled();
});

test('cancelPrebuild는 핸들이 있을 때만 네이티브를 부른다', () => {
  const index = createSearchIndex();
  index.cancelPrebuild();
  expect(cancelSearchCorePrebuild).not.toHaveBeenCalled();
  index.prebuild([text]);
  index.cancelPrebuild();
  expect(cancelSearchCorePrebuild).toHaveBeenCalledTimes(1);
  index.dispose();
});

test('dispose는 핸들을 해제하고 다음 호출이 새 핸들을 만든다', () => {
  const index = createSearchIndex();
  const clips = [text];
  index.prebuild(clips);
  index.dispose();
  expect(freeSearchCore).toHaveBeenCalledTimes(1);
  index.dispose();
  expect(freeSearchCore).toHaveBeenCalledTimes(1);
  index.prebuild(clips);
  expect(createSearchCore).toHaveBeenCalledTimes(2);
  expect(syncSearchCore).toHaveBeenCalledTimes(2);
  index.dispose();
});
