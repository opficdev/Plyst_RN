import {
  configureStore,
  createListenerMiddleware,
  Tuple,
} from '@reduxjs/toolkit';
import type { Action, Dispatch } from '@reduxjs/toolkit';
import { useDispatch, useSelector } from 'react-redux';

export { createAction } from '@reduxjs/toolkit';
export { Provider as ScreenProvider } from 'react-redux';

export type ScreenScope<State> = {
  getState: () => State;
  dispatch: Dispatch;
  isDisposed: () => boolean;
  onDispose: (cleanup: () => void) => void;
  listen: <Intent extends Action>(
    creator: { match: (action: unknown) => action is Intent },
    effect: (action: Intent) => void | Promise<void>,
  ) => void;
};

export function createScreenStore<State, Mutation extends Action>({
  initialState,
  reduce,
  mutations,
  start,
}: {
  initialState: () => State;
  reduce: (state: State, action: Mutation) => State;
  mutations: Record<Mutation['type'], true>;
  start: (scope: ScreenScope<State>) => void;
}) {
  const listener = createListenerMiddleware<State>();
  const reset = { type: 'screen/reset' };
  const store = configureStore({
    reducer: (state = initialState(), action): State => {
      if (action === reset) return initialState();
      return Object.prototype.hasOwnProperty.call(mutations, action.type)
        ? reduce(state, action as Mutation)
        : state;
    },
    middleware: () => new Tuple(listener.middleware),
  });
  let stop: (() => void) | undefined;
  let hasStarted = false;

  return {
    store,
    start() {
      if (stop) return;
      if (hasStarted) store.dispatch(reset);
      hasStarted = true;
      // 종료된 세션의 비동기 작업은 새 세션이 시작돼도 다시 활성화되지 않습니다.
      let disposed = false;
      const cleanups: (() => void)[] = [];
      const scope: ScreenScope<State> = {
        getState: store.getState,
        dispatch: (action) => {
          if (!disposed) store.dispatch(action);
          return action;
        },
        isDisposed: () => disposed,
        onDispose(cleanup) {
          if (disposed) cleanup();
          else cleanups.push(cleanup);
        },
        listen(creator, effect) {
          const unsubscribe = listener.startListening({
            predicate: creator.match,
            effect: (action) => {
              if (!disposed) return effect(action);
            },
          });
          scope.onDispose(() => unsubscribe({ cancelActive: true }));
        },
      };
      stop = () => {
        disposed = true;
        stop = undefined;
        for (const cleanup of cleanups.reverse()) cleanup();
      };
      start(scope);
    },
    dispose() {
      stop?.();
    },
  };
}

export function useScreenState<State>() {
  return useSelector((state: State) => state, {
    devModeChecks: { identityFunctionCheck: 'never' },
  });
}

export const useScreenDispatch = useDispatch;
