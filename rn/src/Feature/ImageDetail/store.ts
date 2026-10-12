import { createScreenStore } from '../../Shared/State/screenStore';
import { initialState, reduce } from './draft';
import type { ImageDetailAction, ImageDetailState } from './draft';
import { startImageDetailListeners } from './listeners';

export type ImageDetailStoreState = ImageDetailState | null | 'closed';
type Action = ImageDetailAction | { type: 'loadFailed' };

function reduceContent(
  state: ImageDetailStoreState,
  action: Action,
): ImageDetailStoreState {
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

export function createImageDetailStore(clipID: string) {
  return createScreenStore({
    initialState: (): ImageDetailStoreState => null,
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
      photoSaveStarted: true,
      photoSaveFinished: true,
      previewReady: true,
      previewLoaded: true,
      previewFailed: true,
    },
    start: (scope) => startImageDetailListeners(scope, clipID),
  });
}
