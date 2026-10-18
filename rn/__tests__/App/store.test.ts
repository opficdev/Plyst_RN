import { createAppStore } from '../../src/App/store';

test('이동 상태를 store에서 바꾸고 다시 시작하면 처음 상태로 돌아간다', () => {
  const screen = createAppStore();
  screen.start();
  screen.store.dispatch({ type: 'searchOpened' });
  screen.store.dispatch({
    type: 'clipOpened',
    detail: { clipID: 'clip', kind: 'image' },
  });
  expect(screen.store.getState()).toEqual({
    isSearchVisible: true,
    detail: { clipID: 'clip', kind: 'image' },
  });
  screen.store.dispatch({ type: 'clipClosed' });
  expect(screen.store.getState().detail).toBeNull();
  screen.dispose();
  screen.start();
  expect(screen.store.getState()).toEqual({
    isSearchVisible: false,
    detail: null,
  });
  screen.dispose();
});

test('이동 상태에 없는 액션은 상태를 바꾸지 않는다', () => {
  const screen = createAppStore();
  screen.start();
  const before = screen.store.getState();
  screen.store.dispatch({ type: 'unknown' });
  expect(screen.store.getState()).toBe(before);
  screen.dispose();
});
