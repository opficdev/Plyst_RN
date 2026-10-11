import type { ClipRecord } from 'plyst-bridge';
import {
  clipThumbnailLimit,
  reduceClipThumbnails,
  retainClipThumbnails,
} from '../../../src/Feature/ClipGrid/clipThumbnails';
import type { ClipThumbnails } from '../../../src/Feature/ClipGrid/clipThumbnails';

const clip: ClipRecord = {
  id: 'image',
  text: null,
  name: null,
  image: {
    byteCountText: '100 B',
    contentType: 'public.png',
    pixelWidth: 10,
    pixelHeight: 10,
  },
  memo: null,
  isPinned: false,
  isWebLink: false,
  characterCount: 0,
  textPrefix: null,
  createdAt: 0,
  lastUsedAt: null,
};
const empty = (): ClipThumbnails => ({
  thumbnails: {},
  thumbnailOrder: [],
  loadingThumbnails: {},
  failedThumbnails: {},
});
function load(state: ClipThumbnails, key: string) {
  return reduceClipThumbnails(
    reduceClipThumbnails(state, { type: 'thumbnailStarted', key }, [clip]),
    { type: 'thumbnailLoaded', key, uri: `file:///${key}` },
    [clip],
  );
}

test('시작한 이미지 요청만 성공 캐시에 넣는다', () => {
  const state = empty();
  expect(
    reduceClipThumbnails(
      state,
      {
        type: 'thumbnailLoaded',
        key: 'image:100',
        uri: 'file:///image',
      },
      [clip],
    ),
  ).toEqual(state);
  expect(load(state, 'image:100')).toEqual({
    thumbnails: { 'image:100': 'file:///image:100' },
    thumbnailOrder: ['image:100'],
    loadingThumbnails: {},
    failedThumbnails: {},
  });
});

test('실패와 취소는 진행 상태를 제거하고 실패 기록은 보존한다', () => {
  const started = reduceClipThumbnails(
    empty(),
    {
      type: 'thumbnailStarted',
      key: 'image:100',
    },
    [clip],
  );
  const failed = reduceClipThumbnails(
    started,
    {
      type: 'thumbnailFailed',
      key: 'image:100',
    },
    [clip],
  );
  expect(failed.loadingThumbnails).toEqual({});
  expect(failed.failedThumbnails).toEqual({ 'image:100': true });
  expect(
    reduceClipThumbnails(
      failed,
      {
        type: 'thumbnailCancelled',
        key: 'image:100',
      },
      [clip],
    ),
  ).toEqual(failed);
});

test('취소 뒤 도착한 응답은 캐시를 바꾸지 않는다', () => {
  const state = reduceClipThumbnails(
    empty(),
    {
      type: 'thumbnailStarted',
      key: 'image:100',
    },
    [clip],
  );
  const cancelled = reduceClipThumbnails(
    state,
    {
      type: 'thumbnailCancelled',
      key: 'image:100',
    },
    [clip],
  );
  expect(
    reduceClipThumbnails(
      cancelled,
      {
        type: 'thumbnailLoaded',
        key: 'image:100',
        uri: 'file:///image',
      },
      [clip],
    ),
  ).toEqual(cancelled);
});

test('유효한 이미지 id의 모든 크기만 보존한다', () => {
  const state = {
    ...load(empty(), 'image:100'),
    loadingThumbnails: {
      'image:200': true as const,
      'gone:100': true as const,
    },
    failedThumbnails: { 'image:300': true as const, 'gone:200': true as const },
  };
  expect(retainClipThumbnails(state, [clip])).toEqual({
    ...state,
    loadingThumbnails: { 'image:200': true },
    failedThumbnails: { 'image:300': true },
  });
  expect(retainClipThumbnails(state, [])).toEqual(empty());
  expect(
    retainClipThumbnails(state, [{ ...clip, image: null, text: '본문' }]),
  ).toEqual(empty());
});

test('캐시는 48개를 유지하고 갱신한 키를 가장 뒤로 옮긴다', () => {
  expect(clipThumbnailLimit).toBe(48);
  let state = empty();
  for (let i = 1; i <= 48; i += 1) state = load(state, `image:${i}`);
  state = load(state, 'image:1');
  state = load(state, 'image:49');
  expect(state.thumbnailOrder).toHaveLength(48);
  expect(state.thumbnailOrder.slice(-2)).toEqual(['image:1', 'image:49']);
  expect(state.thumbnails['image:2']).toBeUndefined();
});

test('삭제된 이미지의 늦은 응답은 진행 표시만 제거한다', () => {
  const state = reduceClipThumbnails(
    empty(),
    {
      type: 'thumbnailStarted',
      key: 'image:100',
    },
    [clip],
  );
  expect(
    reduceClipThumbnails(
      state,
      {
        type: 'thumbnailLoaded',
        key: 'image:100',
        uri: 'file:///image',
      },
      [],
    ),
  ).toEqual(empty());
});

test('입력 슬라이스를 변경하지 않는다', () => {
  const state = load(empty(), 'image:100');
  const before = JSON.parse(JSON.stringify(state));
  Object.freeze(state);
  Object.freeze(state.thumbnails);
  Object.freeze(state.thumbnailOrder);
  Object.freeze(state.loadingThumbnails);
  Object.freeze(state.failedThumbnails);
  load(state, 'image:200');
  retainClipThumbnails(state, []);
  expect(state).toEqual(before);
});
