import { sortPinnedClips } from '../../src/Model/clipPinOrder';
import { makeClipRecord } from '../../src/Model/clipRecord';

const clip = makeClipRecord({
  id: '00000000-0000-0000-0000-000000000001',
  text: '원문',
  image: null,
  name: null,
  memo: null,
  pinnedAt: 100,
  isWebLink: false,
  createdAt: 10,
  lastUsedAt: null,
});

test('생성 시각과 무관하게 최근에 고정한 클립이 먼저 온다', () => {
  const recent = { ...clip, id: 'B', createdAt: 1, pinnedAt: 200 };
  expect(sortPinnedClips([clip, recent])).toEqual([recent, clip]);
});

test('해제한 뒤 다시 고정하면 새 고정 시각으로 앞으로 이동한다', () => {
  const other = { ...clip, id: 'B', pinnedAt: 200 };
  const unpinned = { ...clip, pinnedAt: null };
  const repinned = { ...unpinned, pinnedAt: 300 };
  expect(sortPinnedClips([clip, other])).toEqual([other, clip]);
  expect(sortPinnedClips([other, repinned])).toEqual([repinned, other]);
});

test('고정 시각이 같으면 생성 시각 내림차순과 식별자 오름차순으로 정렬한다', () => {
  const first = { ...clip, id: 'A', createdAt: 20 };
  const second = { ...first, id: 'B' };
  const older = { ...clip, id: '0' };
  expect(sortPinnedClips([older, second, first])).toEqual([
    first,
    second,
    older,
  ]);
});

test('입력 배열을 변경하지 않고 새 배열을 반환한다', () => {
  const recent = { ...clip, id: 'B', pinnedAt: 200 };
  const input = Object.freeze([Object.freeze(clip), Object.freeze(recent)]);
  const sorted = sortPinnedClips(input);
  expect(sorted).not.toBe(input);
  expect(input).toEqual([clip, recent]);
  expect(sorted).toEqual([recent, clip]);
});

test('고정 시각이 null이면 생성 시각을 사용한다', () => {
  const fallback = { ...clip, id: 'B', pinnedAt: null, createdAt: 200 };
  expect(sortPinnedClips([clip, fallback])).toEqual([fallback, clip]);
});
