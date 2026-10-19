import {
  createAction,
  createScreenStore,
  createSliceStore,
  createSlice,
  untilAborted,
} from '../../../src/Shared/State/screenStore';
import type {
  PayloadAction,
  ScreenScope,
  SliceListen,
} from '../../../src/Shared/State/screenStore';

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

const counter = createSlice({
  name: 'counter',
  initialState: () => ({ value: 0 }),
  reducers: {
    changed(state, { payload }: PayloadAction<number>) {
      state.value = payload;
    },
    requested() {},
  },
});
type Counter = ReturnType<typeof counter.getInitialState>;
function makeSliceScreen(
  start: (listen: SliceListen<Counter>) => void | (() => void),
) {
  return createSliceStore({ slice: counter, start });
}

test('slice: 알 수 없는 Action은 상태를 바꾸지 않고 이름이 같은 reset 객체는 초기화하지 않는다', () => {
  const screen = makeSliceScreen(() => {});
  screen.store.dispatch(counter.actions.changed(7));
  for (const type of ['unknown', 'counter/unknown', 'screen/reset']) {
    screen.store.dispatch({ type });
    expect(screen.store.getState()).toEqual({ value: 7 });
  }
});

test('slice: 생성은 자원을 연결하지 않고 중복 시작과 종료는 한 번만 처리한다', () => {
  const effect = jest.fn();
  const start = jest.fn((listen: SliceListen<Counter>) => {
    listen({ actionCreator: counter.actions.requested, effect });
  });
  const screen = makeSliceScreen(start);
  expect(start).not.toHaveBeenCalled();
  screen.start();
  screen.start();
  expect(start).toHaveBeenCalledTimes(1);
  screen.store.dispatch(counter.actions.requested());
  expect(effect).toHaveBeenCalledTimes(1);
  screen.dispose();
  screen.dispose();
  screen.store.dispatch(counter.actions.requested());
  expect(effect).toHaveBeenCalledTimes(1);
});

test('slice: 종료는 listener를 끊은 다음 start가 돌려준 정리 함수를 한 번 실행한다', () => {
  const order: string[] = [];
  const screen = makeSliceScreen((listen) => {
    listen({
      actionCreator: counter.actions.requested,
      effect: async (_, api) => {
        await untilAborted(api.signal, () => order.push('abort'));
      },
    });
    return () => order.push('cleanup');
  });
  screen.start();
  screen.store.dispatch(counter.actions.requested());
  screen.dispose();
  screen.dispose();
  expect(order).toEqual(['abort', 'cleanup']);
});

test('slice: 재시작은 상태를 초기화하고 이전 세션의 effect를 abort한다', async () => {
  let finish!: () => void;
  const pending = new Promise<void>((resolve) => {
    finish = resolve;
  });
  const signals: AbortSignal[] = [];
  const screen = makeSliceScreen((listen) => {
    listen({
      actionCreator: counter.actions.requested,
      effect: async (_, api) => {
        signals.push(api.signal);
        await pending;
        if (!api.signal.aborted) api.dispatch(counter.actions.changed(99));
      },
    });
  });
  screen.start();
  screen.store.dispatch(counter.actions.requested());
  screen.store.dispatch(counter.actions.changed(1));
  screen.dispose();
  expect(signals[0].aborted).toBe(true);
  screen.start();
  expect(screen.store.getState()).toEqual({ value: 0 });
  finish();
  await pending;
  expect(screen.store.getState()).toEqual({ value: 0 });
  screen.dispose();
});

test('slice: 두 화면은 상태와 listener를 공유하지 않는다', () => {
  const start = (listen: SliceListen<Counter>) => {
    listen({
      actionCreator: counter.actions.requested,
      effect: (_, api) => {
        api.dispatch(counter.actions.changed(3));
      },
    });
  };
  const first = makeSliceScreen(start);
  const second = makeSliceScreen(start);
  first.start();
  second.start();
  first.store.dispatch(counter.actions.requested());
  expect(first.store.getState()).toEqual({ value: 3 });
  expect(second.store.getState()).toEqual({ value: 0 });
  first.dispose();
  second.dispose();
});

test('slice: start가 받은 dispatch는 listener 밖에서도 store에 action을 보낸다', () => {
  let dispatch:
    | ((action: ReturnType<typeof counter.actions.changed>) => unknown)
    | undefined;
  const screen = createSliceStore({
    slice: counter,
    start: (_, send) => {
      dispatch = send;
    },
  });
  screen.start();
  dispatch?.(counter.actions.changed(5));
  expect(screen.store.getState()).toEqual({ value: 5 });
  screen.dispose();
});
