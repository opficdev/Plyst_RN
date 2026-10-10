import type { ClipRecord } from 'plyst-bridge';
import {
  homeThumbnailLimit,
  initialState,
  reduce,
} from '../src/screens/homeState';
import type { HomeAction, HomeState } from '../src/screens/homeState';

const clip: ClipRecord = {
  id: 'image',
  text: null,
  characterCount: 0,
  textPrefix: null,
  isWebLink: false,
  image: {
    byteCountText: '1 KB',
    contentType: 'public.png',
    pixelWidth: 10,
    pixelHeight: 10,
  },
  name: null,
  memo: null,
  isPinned: false,
  createdAt: 1234500,
  lastUsedAt: null,
};
const key = 'image:200';
const uri = 'file:///thumbnail.png';
const loaded = () =>
  reduce(initialState(1000), { type: 'clipsLoaded', clips: [clip], now: 2000 });

function loadThumbnail(
  state: HomeState,
  key: string,
  uri = 'file:///thumbnail.png',
) {
  return reduce(reduce(state, { type: 'thumbnailStarted', key }), {
    type: 'thumbnailLoaded',
    key,
    uri,
  });
}

test('초기 상태는 지정한 시각과 빈 목록 및 캐시를 가진다', () => {
  expect(initialState(1000)).toEqual({
    loadPhase: 'loading',
    clips: [],
    now: 1000,
    filter: 'all',
    thumbnails: {},
    thumbnailOrder: [],
    loadingThumbnails: {},
    failedThumbnails: {},
    isSearchVisible: false,
    isSaving: false,
    menuClip: null,
    isMenuVisible: false,
    isDeleteConfirmVisible: false,
  });
  const first = initialState(1000);
  first.thumbnailOrder.push(key);
  expect(initialState(1000).thumbnailOrder).toEqual([]);
});

test('목록을 읽으면 시각과 조회 단계를 갱신한다', () => {
  expect(loaded()).toEqual({
    ...initialState(1000),
    loadPhase: 'loaded',
    clips: [clip],
    now: 2000,
  });
});

test.each<[HomeAction, Partial<HomeState>]>([
  [{ type: 'loadFailed' }, { loadPhase: 'failed' }],
  [{ type: 'timeChanged', now: 3000 }, { now: 3000 }],
  [{ type: 'filterSelected', filter: 'image' }, { filter: 'image' }],
  [
    { type: 'searchVisibilityChanged', isVisible: true },
    { isSearchVisible: true },
  ],
  [{ type: 'thumbnailStarted', key }, { loadingThumbnails: { [key]: true } }],
])('%j는 해당 상태만 바꾼다', (action, change) => {
  const state = loaded();
  expect(reduce(state, action)).toEqual({ ...state, ...change });
});

test('같은 필터 선택은 동일한 상태를 반환한다', () => {
  const state = loaded();
  expect(reduce(state, { type: 'filterSelected', filter: 'all' })).toBe(state);
});

test('검색 화면이 닫히면 표시 상태만 해제한다', () => {
  const state = { ...loaded(), isSearchVisible: true };
  expect(
    reduce(state, { type: 'searchVisibilityChanged', isVisible: false }),
  ).toEqual({ ...state, isSearchVisible: false });
});

test('시작된 이미지 요청만 캐시에 넣고 로딩 상태를 지운다', () => {
  const state = loaded();
  expect(reduce(state, { type: 'thumbnailLoaded', key, uri })).toEqual(state);
  expect(loadThumbnail(state, key)).toEqual({
    ...state,
    thumbnails: { [key]: uri },
    thumbnailOrder: [key],
    loadingThumbnails: {},
  });
});

test.each<{ clips: ClipRecord[] }>([
  { clips: [] },
  { clips: [{ ...clip, image: null, text: '원문', textPrefix: '원문' }] },
])('이미지가 사라진 응답은 로딩 표시만 지운다', ({ clips }) => {
  const state = {
    ...loaded(),
    clips,
    loadingThumbnails: { [key]: true as const },
  };
  expect(reduce(state, { type: 'thumbnailLoaded', key, uri })).toEqual({
    ...state,
    loadingThumbnails: {},
  });
});

test('실패는 로딩을 지우고 실패 기록을 남긴다', () => {
  const state = reduce(loaded(), { type: 'thumbnailStarted', key });
  const failed = reduce(state, { type: 'thumbnailFailed', key });
  expect(failed).toEqual({
    ...state,
    loadingThumbnails: {},
    failedThumbnails: { [key]: true },
  });
  expect(
    reduce(loaded(), { type: 'thumbnailFailed', key }).failedThumbnails,
  ).toEqual({ [key]: true });
});

test('취소는 실패와 캐시를 보존하고 로딩만 지운다', () => {
  const state = {
    ...loadThumbnail(loaded(), key),
    loadingThumbnails: { [key]: true as const },
    failedThumbnails: { [key]: true as const },
  };
  expect(reduce(state, { type: 'thumbnailCancelled', key })).toEqual({
    ...state,
    loadingThumbnails: {},
  });
});

test('시작과 성공은 기존 실패 기록을 지우지 않는다', () => {
  const state = { ...loaded(), failedThumbnails: { [key]: true as const } };
  expect(loadThumbnail(state, key).failedThumbnails).toEqual({ [key]: true });
});

test('48개를 유지하고 다시 받은 키를 맨 뒤로 옮긴 후 가장 오래된 키를 제거한다', () => {
  expect(homeThumbnailLimit).toBe(48);
  let state = loaded();
  for (let pixels = 1; pixels <= 48; pixels += 1)
    state = loadThumbnail(state, `image:${pixels}`);
  expect(state.thumbnailOrder).toEqual(
    Array.from({ length: 48 }, (_, index) => `image:${index + 1}`),
  );
  expect(Object.keys(state.thumbnails)).toHaveLength(48);
  state = loadThumbnail(state, 'image:1', 'file:///updated.png');
  expect(state.thumbnailOrder).toEqual([
    ...Array.from({ length: 47 }, (_, index) => `image:${index + 2}`),
    'image:1',
  ]);
  state = loadThumbnail(state, 'image:49');
  expect(state.thumbnailOrder).toEqual([
    ...Array.from({ length: 46 }, (_, index) => `image:${index + 3}`),
    'image:1',
    'image:49',
  ]);
  expect(state.thumbnails['image:2']).toBeUndefined();
  expect(state.thumbnails['image:1']).toBe('file:///updated.png');
  expect(Object.keys(state.thumbnails)).toHaveLength(48);
});

test('목록 갱신은 이미지로 남아 있는 클립의 모든 크기만 보존한다', () => {
  const state: HomeState = {
    ...loaded(),
    filter: 'pinned',
    isSearchVisible: true,
    thumbnails: {
      'image:100': uri,
      'gone:100': uri,
      'text:100': uri,
      'image:200': uri,
    },
    thumbnailOrder: ['image:100', 'gone:100', 'text:100', 'image:200'],
    loadingThumbnails: {
      'image:300': true,
      'gone:300': true,
      'text:300': true,
    },
    failedThumbnails: { 'image:400': true, 'gone:400': true, 'text:400': true },
  };
  const clips = [
    clip,
    { ...clip, id: 'text', image: null, text: '원문', textPrefix: '원문' },
  ];
  expect(reduce(state, { type: 'clipsLoaded', clips, now: 5000 })).toEqual({
    ...state,
    clips,
    now: 5000,
    thumbnails: { 'image:100': uri, 'image:200': uri },
    thumbnailOrder: ['image:100', 'image:200'],
    loadingThumbnails: { 'image:300': true },
    failedThumbnails: { 'image:400': true },
  });
  expect(reduce(state, { type: 'clipsLoaded', clips: [], now: 5000 })).toEqual({
    ...state,
    clips: [],
    now: 5000,
    thumbnails: {},
    thumbnailOrder: [],
    loadingThumbnails: {},
    failedThumbnails: {},
  });
});

test('취소 후 도착한 성공 응답은 캐시에 넣지 않는다', () => {
  const state = reduce(reduce(loaded(), { type: 'thumbnailStarted', key }), {
    type: 'thumbnailCancelled',
    key,
  });
  expect(reduce(state, { type: 'thumbnailLoaded', key, uri })).toEqual(state);
});

test.each<HomeAction>([
  { type: 'savingStarted' },
  { type: 'savingStopped' },
  { type: 'menuShown', clip },
  { type: 'menuClosed' },
  { type: 'deleteConfirmShown', clip },
  { type: 'deleteConfirmClosed' },
  { type: 'clipsLoaded', clips: [clip], now: 3000 },
  { type: 'loadFailed' },
  { type: 'timeChanged', now: 3000 },
  { type: 'filterSelected', filter: 'text' },
  { type: 'thumbnailStarted', key },
  { type: 'thumbnailLoaded', key, uri },
  { type: 'thumbnailFailed', key },
  { type: 'thumbnailCancelled', key },
  { type: 'searchVisibilityChanged', isVisible: true },
])('%j는 입력 상태를 변형하지 않는다', (action) => {
  const state = loadThumbnail(loaded(), key);
  state.loadingThumbnails[key] = true;
  const before = JSON.parse(JSON.stringify(state));
  Object.freeze(state.thumbnails);
  Object.freeze(state.thumbnailOrder);
  Object.freeze(state.loadingThumbnails);
  Object.freeze(state.failedThumbnails);
  Object.freeze(state.clips);
  Object.freeze(state);
  reduce(state, Object.freeze(action));
  expect(state).toEqual(before);
});

test('저장 시작과 종료는 저장 상태만 변경한다', () => {
  const state = loaded();
  const saving = reduce(state, { type: 'savingStarted' });
  expect(saving).toEqual({ ...state, isSaving: true });
  expect(reduce(saving, { type: 'savingStarted' })).toEqual(saving);
  expect(reduce(saving, { type: 'savingStopped' })).toEqual(state);
});

test('메뉴와 삭제 확인을 취소해도 클립은 바뀌지 않는다', () => {
  const state = loaded();
  const menu = reduce(state, { type: 'menuShown', clip });
  expect(menu).toEqual({ ...state, menuClip: clip, isMenuVisible: true });
  const closed = reduce(menu, { type: 'menuClosed' });
  expect(closed).toEqual({ ...menu, isMenuVisible: false });
  expect(closed.clips).toBe(state.clips);
  expect(closed.menuClip).toBe(clip);
  const confirmation = reduce(closed, { type: 'deleteConfirmShown', clip });
  expect(confirmation).toEqual({ ...closed, isDeleteConfirmVisible: true });
  const cancelled = reduce(confirmation, { type: 'deleteConfirmClosed' });
  expect(cancelled).toEqual(closed);
  expect(cancelled.clips).toBe(state.clips);
});

test('열린 메뉴와 삭제 확인 위에 새 메뉴를 열지 않는다', () => {
  const menu = reduce(loaded(), { type: 'menuShown', clip });
  const action = { type: 'menuShown', clip: { ...clip, id: 'other' } } as const;
  expect(reduce(menu, action)).toBe(menu);
  const confirmation = reduce(reduce(menu, { type: 'menuClosed' }), {
    type: 'deleteConfirmShown',
    clip,
  });
  expect(reduce(confirmation, action)).toBe(confirmation);
});

test('목록에서 삭제되어도 시트가 닫히는 동안 메뉴 내용은 유지한다', () => {
  const menu = reduce(loaded(), { type: 'menuShown', clip });
  const refreshed = reduce(menu, { type: 'clipsLoaded', clips: [], now: 3000 });
  expect(refreshed.menuClip).toBe(clip);
  expect(refreshed.isMenuVisible).toBe(true);
  expect(refreshed.clips).toEqual([]);
});
