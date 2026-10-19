import {
  createScreenStore,
  createSlice,
  untilAborted,
} from '../../../src/Shared/State/screenStore';
import type {
  PayloadAction,
  SliceListen,
} from '../../../src/Shared/State/screenStore';

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
function makeScreen(
  start: (listen: SliceListen<Counter>) => void | (() => void),
) {
  return createScreenStore({ slice: counter, start });
}

test('알 수 없는 Action은 상태를 바꾸지 않고 이름이 같은 reset 객체는 초기화하지 않는다', () => {
  const screen = makeScreen(() => {});
  screen.store.dispatch(counter.actions.changed(7));
  for (const type of ['unknown', 'counter/unknown', 'screen/reset']) {
    screen.store.dispatch({ type });
    expect(screen.store.getState()).toEqual({ value: 7 });
  }
});

test('생성은 자원을 연결하지 않고 중복 시작과 종료는 한 번만 처리한다', () => {
  const effect = jest.fn();
  const start = jest.fn((listen: SliceListen<Counter>) => {
    listen({ actionCreator: counter.actions.requested, effect });
  });
  const screen = makeScreen(start);
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

test('종료는 listener를 끊은 다음 start가 돌려준 정리 함수를 한 번 실행한다', () => {
  const order: string[] = [];
  const screen = makeScreen((listen) => {
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

test('재시작은 상태를 초기화하고 이전 세션의 effect를 abort한다', async () => {
  let finish!: () => void;
  const pending = new Promise<void>((resolve) => {
    finish = resolve;
  });
  const signals: AbortSignal[] = [];
  const screen = makeScreen((listen) => {
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

test('두 화면은 상태와 listener를 공유하지 않는다', () => {
  const start = (listen: SliceListen<Counter>) => {
    listen({
      actionCreator: counter.actions.requested,
      effect: (_, api) => {
        api.dispatch(counter.actions.changed(3));
      },
    });
  };
  const first = makeScreen(start);
  const second = makeScreen(start);
  first.start();
  second.start();
  first.store.dispatch(counter.actions.requested());
  expect(first.store.getState()).toEqual({ value: 3 });
  expect(second.store.getState()).toEqual({ value: 0 });
  first.dispose();
  second.dispose();
});

test('start가 받은 dispatch는 listener 밖에서도 store에 action을 보낸다', () => {
  let dispatch:
    | ((action: ReturnType<typeof counter.actions.changed>) => unknown)
    | undefined;
  const screen = createScreenStore({
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
