import {
  initialNavigation,
  navigationActions as actions,
  navigationSlice,
} from '../../src/App/navigation';
import type { AppNavigation } from '../../src/App/navigation';

const detail = { clipID: 'clip', kind: 'text' } as const;
const other = { clipID: 'other', kind: 'image' } as const;
type Action = Parameters<typeof navigationSlice.reducer>[1];

function reduce(state: AppNavigation, action: Action) {
  return navigationSlice.reducer(state, action);
}

test('초기 상태는 검색과 상세가 모두 닫혀 있다', () => {
  expect(initialNavigation()).toEqual({
    isSearchVisible: false,
    detail: null,
  });
  expect(navigationSlice.getInitialState()).toEqual(initialNavigation());
});

test('검색을 열고 닫는다', () => {
  const opened = reduce(initialNavigation(), actions.searchOpened());
  expect(opened).toEqual({ isSearchVisible: true, detail: null });
  expect(reduce(opened, actions.searchClosed())).toEqual(initialNavigation());
});

test('이미 열린 검색을 다시 열거나 닫힌 검색을 닫으면 같은 상태를 반환한다', () => {
  const closed = initialNavigation();
  expect(reduce(closed, actions.searchClosed())).toBe(closed);
  const opened: AppNavigation = { isSearchVisible: true, detail: null };
  expect(reduce(opened, actions.searchOpened())).toBe(opened);
});

test('상세가 열려 있으면 검색을 열지 않는다', () => {
  const state: AppNavigation = { isSearchVisible: false, detail };
  expect(reduce(state, actions.searchOpened())).toBe(state);
});

test('검색이 열려 있어도 상세를 열 수 있고 검색은 유지한다', () => {
  const state: AppNavigation = { isSearchVisible: true, detail: null };
  expect(reduce(state, actions.clipOpened(detail))).toEqual({
    isSearchVisible: true,
    detail,
  });
});

test('상세가 열려 있거나 닫히는 중이면 다시 열지 않는다', () => {
  const state: AppNavigation = { isSearchVisible: false, detail };
  expect(reduce(state, actions.clipOpened(other))).toBe(state);
});

test('상세를 닫으면 detail만 비운다', () => {
  const state: AppNavigation = { isSearchVisible: true, detail };
  expect(reduce(state, actions.clipClosed())).toEqual({
    isSearchVisible: true,
    detail: null,
  });
  const closed = initialNavigation();
  expect(reduce(closed, actions.clipClosed())).toBe(closed);
});

test.each([
  actions.searchOpened(),
  actions.searchClosed(),
  actions.clipOpened(detail),
  actions.clipClosed(),
])('%j는 입력 상태를 변형하지 않는다', (action) => {
  const state: AppNavigation = Object.freeze({
    isSearchVisible: true,
    detail,
  });
  reduce(state, action);
  expect(state).toEqual({ isSearchVisible: true, detail });
});
