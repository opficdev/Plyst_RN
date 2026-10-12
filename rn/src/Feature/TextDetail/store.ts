import { createScreenStore } from '../../Shared/State/screenStore';
import { initialState, reduce } from './draft';
import type { TextDetailAction, TextDetailState } from './draft';
import { startTextDetailListeners } from './listeners';

export type TextDetailStoreState = TextDetailState | null | 'closed';
type Action = TextDetailAction | { type: 'loadFailed' };

function reduceContent(
  state: TextDetailStoreState,
  action: Action,
): TextDetailStoreState {
  if (state === 'closed') return state;
  if (action.type === 'loadFailed') return state ?? 'closed';
  if (state === null) {
    if (action.type === 'clipLoaded') return initialState(action.clip);
    return action.type === 'removed' ? 'closed' : state;
  }
  if (action.type === 'clipLoaded' && (state.isRemoved || state.isSaved)) {
    return state;
  }
  return reduce(state, action);
}

export function createTextDetailStore(clipID: string) {
  return createScreenStore({
    initialState: (): TextDetailStoreState => null,
    reduce: reduceContent,
    mutations: {
      clipLoaded: true,
      removed: true,
      nameChanged: true,
      pinnedChanged: true,
      saveStarted: true,
      saved: true,
      saveFailed: true,
      deleteSheetShown: true,
      deleteSheetClosed: true,
      deleteStarted: true,
      deleteFailed: true,
      loadFailed: true,
      memoChanged: true,
    },
    start: (scope) => startTextDetailListeners(scope, clipID),
  });
}
