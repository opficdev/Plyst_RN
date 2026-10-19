import {
  configureStore,
  createListenerMiddleware,
  Tuple,
} from '@reduxjs/toolkit';
import type {
  ActionReducerMapBuilder,
  Dispatch,
  PayloadAction,
  Reducer,
  TypedStartListening,
} from '@reduxjs/toolkit';
import { useDispatch, useSelector } from 'react-redux';

export { createAction, createSlice, original } from '@reduxjs/toolkit';
export type { ActionReducerMapBuilder, PayloadAction };
export { Provider as ScreenProvider } from 'react-redux';

export type SliceListen<State> = TypedStartListening<State>;

// abort되면 정리 함수를 바로 실행하고 끝나는 Promise를 돌려줍니다.
// effect가 이 Promise를 기다리면 세션이 끝날 때까지 구독을 소유합니다.
export function untilAborted(signal: AbortSignal, cleanup: () => void) {
  return new Promise<void>((resolve) => {
    signal.addEventListener(
      'abort',
      () => {
        cleanup();
        resolve();
      },
      { once: true },
    );
  });
}

// slice 하나로 reducer와 action 생성자를 만드는 화면용 factory입니다.
// 종료된 세션의 listener는 clearListeners가 끊고 진행 중인 effect의 signal을 abort합니다.
// start가 돌려준 정리 함수는 clearListeners 다음에 실행합니다.
export function createScreenStore<State>({
  slice,
  start,
}: {
  slice: { reducer: Reducer<State>; getInitialState: () => State };
  start: (
    listen: SliceListen<State>,
    dispatch: Dispatch,
  ) => void | (() => void);
}) {
  const listener = createListenerMiddleware<State>();
  const reset = { type: 'screen/reset' };
  const store = configureStore({
    reducer: (state = slice.getInitialState(), action): State =>
      action === reset ? slice.getInitialState() : slice.reducer(state, action),
    middleware: () => new Tuple(listener.middleware),
  });
  let isStarted = false;
  let hasStarted = false;
  let cleanup: void | (() => void);

  return {
    store,
    start() {
      if (isStarted) return;
      if (hasStarted) store.dispatch(reset);
      isStarted = true;
      hasStarted = true;
      cleanup = start(listener.startListening, store.dispatch);
    },
    dispose() {
      if (!isStarted) return;
      isStarted = false;
      listener.clearListeners();
      cleanup?.();
      cleanup = undefined;
    },
  };
}

export function useScreenState<State>() {
  return useSelector((state: State) => state, {
    devModeChecks: { identityFunctionCheck: 'never' },
  });
}

export const useScreenDispatch = useDispatch;
