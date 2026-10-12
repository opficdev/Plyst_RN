import {
  createAction,
  createScreenStore,
} from '../../../src/Shared/State/screenStore';
import type { ScreenScope } from '../../../src/Shared/State/screenStore';

const request = createAction('action/request');
type Mutation = { type: 'changed'; value: number };
function makeScreen(start: (scope: ScreenScope<number>) => void = () => {}) {
  return createScreenStore({
    initialState: () => 0,
    reduce: (_state: number, action: Mutation) => action.value,
    mutations: { changed: true },
    start,
  });
}

test('알 수 없는 Action과 목록의 상속 키는 상태를 변경하지 않는다', () => {
  const screen = makeScreen();
  screen.store.dispatch({ type: 'changed', value: 7 });
  for (const type of [
    'unknown',
    'action/request',
    'toString',
    'constructor',
    'screen/reset',
  ]) {
    screen.store.dispatch({ type });
    expect(screen.store.getState()).toBe(7);
  }
});

test('생성은 자원을 연결하지 않고 중복 시작과 종료는 한 번만 처리한다', () => {
  const cleanup = jest.fn();
  const effect = jest.fn();
  const start = jest.fn((scope: ScreenScope<number>) => {
    scope.onDispose(cleanup);
    scope.listen(request, effect);
  });
  const screen = makeScreen(start);
  expect(start).not.toHaveBeenCalled();
  screen.start();
  screen.start();
  screen.store.dispatch(request());
  expect(effect).toHaveBeenCalledTimes(1);
  screen.dispose();
  screen.dispose();
  screen.store.dispatch(request());
  expect(effect).toHaveBeenCalledTimes(1);
  expect(cleanup).toHaveBeenCalledTimes(1);
});

test('재시작은 상태를 초기화하고 이전 세션의 완료 결과를 차단한다', async () => {
  let finish!: () => void;
  const pending = new Promise<void>((resolve) => {
    finish = resolve;
  });
  const scopes: ScreenScope<number>[] = [];
  const screen = makeScreen((scope) => {
    scopes.push(scope);
    scope.listen(request, async () => {
      await pending;
      scope.dispatch({ type: 'changed', value: 99 });
    });
  });
  screen.start();
  screen.store.dispatch(request());
  screen.store.dispatch({ type: 'changed', value: 1 });
  screen.dispose();
  screen.start();
  expect(screen.store.getState()).toBe(0);
  finish();
  await pending;
  expect(scopes[0].isDisposed()).toBe(true);
  expect(scopes[1].isDisposed()).toBe(false);
  expect(screen.store.getState()).toBe(0);
  screen.dispose();
});

test('같은 팩토리의 두 화면은 상태와 listener를 공유하지 않는다', () => {
  const effect = (scope: ScreenScope<number>) => {
    scope.listen(request, () => {
      scope.dispatch({ type: 'changed', value: 3 });
    });
  };
  const first = makeScreen(effect);
  const second = makeScreen(effect);
  first.start();
  second.start();
  first.store.dispatch(request());
  expect(first.store.getState()).toBe(3);
  expect(second.store.getState()).toBe(0);
  first.dispose();
  second.dispose();
});
