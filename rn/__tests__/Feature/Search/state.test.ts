import type { ClipRecord } from '../../../src/Model/clipRecord';
import { clipGridActions } from '../../../src/Feature/ClipGrid/actions';
import {
  initialSearchState,
  searchActions as actions,
  searchSlice,
} from '../../../src/Feature/Search/state';
import type { SearchState } from '../../../src/Feature/Search/state';

const clip: ClipRecord = {
  id: 'image',
  text: null,
  name: null,
  image: {
    byteCount: 100,
    contentType: 'public.png',
    pixelWidth: 10,
    pixelHeight: 10,
  },
  memo: null,
  pinnedAt: null,
  isWebLink: false,
  characterCount: 0,
  textPrefix: null,
  createdAt: 0,
  lastUsedAt: null,
};
type Action = Parameters<typeof searchSlice.reducer>[1];

function reduce(state: SearchState, action: Action) {
  return searchSlice.reducer(state, action);
}
const loaded = () =>
  reduce(
    initialSearchState(1),
    clipGridActions.clipsLoaded({ clips: [clip], now: 2 }),
  );

test('초기 상태의 목록과 검색어 및 최근 검색어가 비어 있다', () => {
  expect(initialSearchState(1)).toEqual({
    loadPhase: 'loading',
    clips: [],
    now: 1,
    query: '',
    filter: 'all',
    searchHistory: [],
    searchHistoryPhase: 'initial',
    thumbnails: {},
    thumbnailOrder: [],
    loadingThumbnails: {},
    failedThumbnails: {},
  });
  expect(searchSlice.getInitialState().query).toBe('');
});

test('입력과 최근 검색어 선택은 원문만 바꾸고 기록하지 않는다', () => {
  const state = { ...loaded(), searchHistory: ['newer', 'older'] };
  for (const query of ['  fresh ', 'older', '   ']) {
    expect(reduce(state, actions.queryChanged(query))).toEqual({
      ...state,
      query,
    });
  }
});

test('필터는 검색어를 보존하고 같은 값을 선택하면 상태를 유지한다', () => {
  const state = { ...loaded(), query: 'report' };
  expect(reduce(state, clipGridActions.filterSelected('all'))).toBe(state);
  expect(reduce(state, clipGridActions.filterSelected('pinned'))).toEqual({
    ...state,
    filter: 'pinned',
  });
});

test('재조회는 목록과 시각을 갱신하고 실패는 기존 목록을 유지한다', () => {
  const state = loaded();
  expect(state.clips).toEqual([clip]);
  expect(state.now).toBe(2);
  expect(state.loadPhase).toBe('loaded');
  expect(reduce(state, clipGridActions.loadFailed())).toEqual({
    ...state,
    loadPhase: 'failed',
  });
  expect(
    reduce(state, clipGridActions.clipsLoaded({ clips: [], now: 3 })),
  ).toMatchObject({ clips: [], now: 3, loadPhase: 'loaded' });
});

test('시간 변경은 검색 대상 시각만 갱신한다', () => {
  const state = loaded();
  expect(reduce(state, clipGridActions.timeChanged(4))).toEqual({
    ...state,
    now: 4,
  });
});

test('조회와 쓰기 성공 목록은 그대로 반영하고 실패 뒤 삭제로 복구한다', () => {
  let state = initialSearchState(1);
  expect(state.searchHistoryPhase).toBe('initial');
  state = reduce(state, actions.searchHistoryLoaded(['stored']));
  expect(state.searchHistoryPhase).toBe('loaded');
  expect(state.searchHistory).toEqual(['stored']);
  state = reduce(state, actions.searchHistoryLoadFailed());
  expect(state.searchHistoryPhase).toBe('failed');
  expect(state.searchHistory).toEqual(['stored']);
  state = reduce(state, actions.searchHistoryLoaded([]));
  expect(state.searchHistoryPhase).toBe('loaded');
  expect(state.searchHistory).toEqual([]);
});

test('썸네일 시작과 성공 뒤 삭제된 클립의 캐시를 제거한다', () => {
  let state = reduce(loaded(), clipGridActions.thumbnailStarted('image:100'));
  state = reduce(
    state,
    clipGridActions.thumbnailLoaded({
      key: 'image:100',
      uri: 'file:///image',
    }),
  );
  expect(state.thumbnails).toEqual({ 'image:100': 'file:///image' });
  expect(state.loadingThumbnails).toEqual({});
  state = reduce(state, clipGridActions.clipsLoaded({ clips: [], now: 3 }));
  expect(state.thumbnails).toEqual({});
  expect(state.thumbnailOrder).toEqual([]);
});

test('취소 뒤 도착한 응답은 무시하고 실패 기록을 보존한다', () => {
  let state = reduce(loaded(), clipGridActions.thumbnailStarted('image:100'));
  state = reduce(state, clipGridActions.thumbnailCancelled('image:100'));
  expect(
    reduce(
      state,
      clipGridActions.thumbnailLoaded({
        key: 'image:100',
        uri: 'file:///image',
      }),
    ),
  ).toEqual(state);
  state = reduce(state, clipGridActions.thumbnailFailed('image:100'));
  expect(state.failedThumbnails).toEqual({ 'image:100': true });
});

test.each<Action>([
  actions.queryChanged('새 검색어'),
  clipGridActions.filterSelected('image'),
  clipGridActions.clipsLoaded({ clips: [], now: 4 }),
  actions.searchHistoryLoaded(['새 검색어']),
  clipGridActions.thumbnailStarted('image:100'),
  clipGridActions.thumbnailFailed('image:100'),
])('%j는 입력 상태를 변경하지 않는다', (action) => {
  const state = loaded();
  const before = JSON.parse(JSON.stringify(state));
  Object.freeze(state);
  Object.freeze(state.thumbnails);
  Object.freeze(state.loadingThumbnails);
  Object.freeze(state.failedThumbnails);
  Object.freeze(state.thumbnailOrder);
  reduce(state, action);
  expect(state).toEqual(before);
});
