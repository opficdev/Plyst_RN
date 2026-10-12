import type { ClipRecord } from 'plyst-bridge';
import {
  initialSearchState,
  reduceSearch,
} from '../../../src/Feature/Search/state';
import type { SearchAction } from '../../../src/Feature/Search/state';

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
const loaded = () =>
  reduceSearch(initialSearchState(1), {
    type: 'clipsLoaded',
    clips: [clip],
    now: 2,
  });

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
});

test('입력과 최근 검색어 선택은 원문만 바꾸고 기록하지 않는다', () => {
  const state = { ...loaded(), searchHistory: ['newer', 'older'] };
  for (const query of ['  fresh ', 'older', '   ']) {
    expect(reduceSearch(state, { type: 'queryChanged', query })).toEqual({
      ...state,
      query,
    });
  }
});

test('필터는 검색어를 보존하고 같은 값을 선택하면 상태를 유지한다', () => {
  const state = { ...loaded(), query: 'report' };
  expect(reduceSearch(state, { type: 'filterSelected', filter: 'all' })).toBe(
    state,
  );
  expect(
    reduceSearch(state, { type: 'filterSelected', filter: 'pinned' }),
  ).toEqual({ ...state, filter: 'pinned' });
});

test('재조회는 목록과 시각을 갱신하고 실패는 기존 목록을 유지한다', () => {
  const state = loaded();
  expect(state.clips).toEqual([clip]);
  expect(state.now).toBe(2);
  expect(state.loadPhase).toBe('loaded');
  expect(reduceSearch(state, { type: 'loadFailed' })).toEqual({
    ...state,
    loadPhase: 'failed',
  });
  expect(
    reduceSearch(state, { type: 'clipsLoaded', clips: [], now: 3 }),
  ).toMatchObject({ clips: [], now: 3, loadPhase: 'loaded' });
});

test('시간 변경은 검색 대상 시각만 갱신한다', () => {
  const state = loaded();
  expect(reduceSearch(state, { type: 'timeChanged', now: 4 })).toEqual({
    ...state,
    now: 4,
  });
});

test('조회와 쓰기 성공 목록은 그대로 반영하고 실패 뒤 삭제로 복구한다', () => {
  let state = initialSearchState(1);
  expect(state.searchHistoryPhase).toBe('initial');
  state = reduceSearch(state, {
    type: 'searchHistoryLoaded',
    terms: ['stored'],
  });
  expect(state.searchHistoryPhase).toBe('loaded');
  expect(state.searchHistory).toEqual(['stored']);
  state = reduceSearch(state, { type: 'searchHistoryLoadFailed' });
  expect(state.searchHistoryPhase).toBe('failed');
  expect(state.searchHistory).toEqual(['stored']);
  state = reduceSearch(state, { type: 'searchHistoryLoaded', terms: [] });
  expect(state.searchHistoryPhase).toBe('loaded');
  expect(state.searchHistory).toEqual([]);
});

test('썸네일 시작과 성공 뒤 삭제된 클립의 캐시를 제거한다', () => {
  let state = reduceSearch(loaded(), {
    type: 'thumbnailStarted',
    key: 'image:100',
  });
  state = reduceSearch(state, {
    type: 'thumbnailLoaded',
    key: 'image:100',
    uri: 'file:///image',
  });
  expect(state.thumbnails).toEqual({ 'image:100': 'file:///image' });
  expect(state.loadingThumbnails).toEqual({});
  state = reduceSearch(state, { type: 'clipsLoaded', clips: [], now: 3 });
  expect(state.thumbnails).toEqual({});
  expect(state.thumbnailOrder).toEqual([]);
});

test('취소 뒤 도착한 응답은 무시하고 실패 기록을 보존한다', () => {
  let state = reduceSearch(loaded(), {
    type: 'thumbnailStarted',
    key: 'image:100',
  });
  state = reduceSearch(state, { type: 'thumbnailCancelled', key: 'image:100' });
  expect(
    reduceSearch(state, {
      type: 'thumbnailLoaded',
      key: 'image:100',
      uri: 'file:///image',
    }),
  ).toEqual(state);
  state = reduceSearch(state, { type: 'thumbnailFailed', key: 'image:100' });
  expect(state.failedThumbnails).toEqual({ 'image:100': true });
});

test.each<SearchAction>([
  { type: 'queryChanged', query: '새 검색어' },
  { type: 'filterSelected', filter: 'image' },
  { type: 'clipsLoaded', clips: [], now: 4 },
  { type: 'searchHistoryLoaded', terms: ['새 검색어'] },
  { type: 'thumbnailStarted', key: 'image:100' },
  { type: 'thumbnailFailed', key: 'image:100' },
])('%j는 입력 상태를 변경하지 않는다', (action) => {
  const state = loaded();
  const before = JSON.parse(JSON.stringify(state));
  Object.freeze(state);
  Object.freeze(state.thumbnails);
  Object.freeze(state.loadingThumbnails);
  Object.freeze(state.failedThumbnails);
  Object.freeze(state.thumbnailOrder);
  reduceSearch(state, action);
  expect(state).toEqual(before);
});
