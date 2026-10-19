import { clipThumbnailLimit } from '../../../src/Feature/ClipGrid/thumbnails';
import { clipGridActions } from '../../../src/Feature/ClipGrid/actions';
import type { ClipRecord } from '../../../src/Model/clipRecord';
import {
  homeActions as actions,
  homeSlice,
  initialHomeState,
} from '../../../src/Feature/Home/state';
import type { HomeState } from '../../../src/Feature/Home/state';

const clip: ClipRecord = {
  id: 'image',
  text: null,
  characterCount: 0,
  textPrefix: null,
  isWebLink: false,
  image: {
    byteCount: 1000,
    contentType: 'public.png',
    pixelWidth: 10,
    pixelHeight: 10,
  },
  name: null,
  memo: null,
  pinnedAt: null,
  createdAt: 1234500,
  lastUsedAt: null,
};
const key = 'image:200';
const uri = 'file:///thumbnail.png';
type Action = Parameters<typeof homeSlice.reducer>[1];

function reduce(state: HomeState, action: Action) {
  return homeSlice.reducer(state, action);
}
const loaded = () =>
  reduce(
    initialHomeState(1000),
    clipGridActions.clipsLoaded({ clips: [clip], now: 2000 }),
  );

function loadThumbnail(
  state: HomeState,
  key: string,
  uri = 'file:///thumbnail.png',
) {
  return reduce(
    reduce(state, clipGridActions.thumbnailStarted(key)),
    clipGridActions.thumbnailLoaded({ key, uri }),
  );
}

test('초기 상태는 지정한 시각과 빈 목록 및 캐시를 가진다', () => {
  expect(initialHomeState(1000)).toEqual({
    loadPhase: 'loading',
    clips: [],
    now: 1000,
    filter: 'all',
    thumbnails: {},
    thumbnailOrder: [],
    loadingThumbnails: {},
    failedThumbnails: {},
    isSaving: false,
    menuClip: null,
    isMenuVisible: false,
    isDeleteConfirmVisible: false,
  });
  const first = initialHomeState(1000);
  first.thumbnailOrder.push(key);
  expect(initialHomeState(1000).thumbnailOrder).toEqual([]);
  expect(homeSlice.getInitialState().loadPhase).toBe('loading');
});

test('목록을 읽으면 시각과 조회 단계를 갱신한다', () => {
  expect(loaded()).toEqual({
    ...initialHomeState(1000),
    loadPhase: 'loaded',
    clips: [clip],
    now: 2000,
  });
});

test.each<[Action, Partial<HomeState>]>([
  [clipGridActions.loadFailed(), { loadPhase: 'failed' }],
  [clipGridActions.timeChanged(3000), { now: 3000 }],
  [clipGridActions.filterSelected('image'), { filter: 'image' }],
  [
    clipGridActions.thumbnailStarted(key),
    { loadingThumbnails: { [key]: true } },
  ],
])('%j는 해당 상태만 바꾼다', (action, change) => {
  const state = loaded();
  expect(reduce(state, action)).toEqual({ ...state, ...change });
});

test('같은 필터 선택은 동일한 상태를 반환한다', () => {
  const state = loaded();
  expect(reduce(state, clipGridActions.filterSelected('all'))).toBe(state);
});

test('시작된 이미지 요청만 캐시에 넣고 로딩 상태를 지운다', () => {
  const state = loaded();
  expect(reduce(state, clipGridActions.thumbnailLoaded({ key, uri }))).toEqual(
    state,
  );
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
  expect(reduce(state, clipGridActions.thumbnailLoaded({ key, uri }))).toEqual({
    ...state,
    loadingThumbnails: {},
  });
});

test('실패는 로딩을 지우고 실패 기록을 남긴다', () => {
  const state = reduce(loaded(), clipGridActions.thumbnailStarted(key));
  const failed = reduce(state, clipGridActions.thumbnailFailed(key));
  expect(failed).toEqual({
    ...state,
    loadingThumbnails: {},
    failedThumbnails: { [key]: true },
  });
  expect(
    reduce(loaded(), clipGridActions.thumbnailFailed(key)).failedThumbnails,
  ).toEqual({ [key]: true });
});

test('취소는 실패와 캐시를 보존하고 로딩만 지운다', () => {
  const state = {
    ...loadThumbnail(loaded(), key),
    loadingThumbnails: { [key]: true as const },
    failedThumbnails: { [key]: true as const },
  };
  expect(reduce(state, clipGridActions.thumbnailCancelled(key))).toEqual({
    ...state,
    loadingThumbnails: {},
  });
});

test('시작과 성공은 기존 실패 기록을 지우지 않는다', () => {
  const state = { ...loaded(), failedThumbnails: { [key]: true as const } };
  expect(loadThumbnail(state, key).failedThumbnails).toEqual({ [key]: true });
});

test('48개를 유지하고 다시 받은 키를 맨 뒤로 옮긴 후 가장 오래된 키를 제거한다', () => {
  expect(clipThumbnailLimit).toBe(48);
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
  expect(
    reduce(state, clipGridActions.clipsLoaded({ clips, now: 5000 })),
  ).toEqual({
    ...state,
    clips,
    now: 5000,
    thumbnails: { 'image:100': uri, 'image:200': uri },
    thumbnailOrder: ['image:100', 'image:200'],
    loadingThumbnails: { 'image:300': true },
    failedThumbnails: { 'image:400': true },
  });
  expect(
    reduce(state, clipGridActions.clipsLoaded({ clips: [], now: 5000 })),
  ).toEqual({
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
  const state = reduce(
    reduce(loaded(), clipGridActions.thumbnailStarted(key)),
    clipGridActions.thumbnailCancelled(key),
  );
  expect(reduce(state, clipGridActions.thumbnailLoaded({ key, uri }))).toEqual(
    state,
  );
});

test.each<Action>([
  actions.saveCurrentClipboard(),
  actions.savingStopped(),
  actions.menuShown(clip),
  actions.menuClosed(),
  actions.deleteConfirmShown(clip),
  actions.deleteConfirmClosed(),
  clipGridActions.clipsLoaded({ clips: [clip], now: 3000 }),
  clipGridActions.loadFailed(),
  clipGridActions.timeChanged(3000),
  clipGridActions.filterSelected('text'),
  clipGridActions.thumbnailStarted(key),
  clipGridActions.thumbnailLoaded({ key, uri }),
  clipGridActions.thumbnailFailed(key),
  clipGridActions.thumbnailCancelled(key),
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
  reduce(state, action);
  expect(state).toEqual(before);
});

test('저장 시작과 종료는 저장 상태만 변경한다', () => {
  const state = loaded();
  const saving = reduce(state, actions.saveCurrentClipboard());
  expect(saving).toEqual({ ...state, isSaving: true });
  expect(reduce(saving, actions.saveCurrentClipboard())).toEqual(saving);
  expect(reduce(saving, actions.savingStopped())).toEqual(state);
});

test('메뉴와 삭제 확인을 취소해도 클립은 바뀌지 않는다', () => {
  const state = loaded();
  const menu = reduce(state, actions.menuShown(clip));
  expect(menu).toEqual({ ...state, menuClip: clip, isMenuVisible: true });
  const closed = reduce(menu, actions.menuClosed());
  expect(closed).toEqual({ ...menu, isMenuVisible: false });
  expect(closed.clips).toBe(state.clips);
  expect(closed.menuClip).toEqual(clip);
  const confirmation = reduce(closed, actions.deleteConfirmShown(clip));
  expect(confirmation).toEqual({ ...closed, isDeleteConfirmVisible: true });
  const cancelled = reduce(confirmation, actions.deleteConfirmClosed());
  expect(cancelled).toEqual(closed);
  expect(cancelled.clips).toBe(state.clips);
});

test('열린 메뉴와 삭제 확인 위에 새 메뉴를 열지 않는다', () => {
  const menu = reduce(loaded(), actions.menuShown(clip));
  const action = actions.menuShown({ ...clip, id: 'other' });
  expect(reduce(menu, action)).toBe(menu);
  const confirmation = reduce(
    reduce(menu, actions.menuClosed()),
    actions.deleteConfirmShown(clip),
  );
  expect(reduce(confirmation, action)).toBe(confirmation);
});

test('목록에서 삭제되어도 시트가 닫히는 동안 메뉴 내용은 유지한다', () => {
  const menu = reduce(loaded(), actions.menuShown(clip));
  const refreshed = reduce(
    menu,
    clipGridActions.clipsLoaded({ clips: [], now: 3000 }),
  );
  expect(refreshed.menuClip).toEqual(clip);
  expect(refreshed.isMenuVisible).toBe(true);
  expect(refreshed.clips).toEqual([]);
});
