import { createScreenStore } from '../../Shared/State/screenStore';
import { initialState, reduce } from './state';
import { startHomeListeners } from './listeners';

export function createHomeStore() {
  return createScreenStore({
    initialState: () => initialState(Date.now()),
    reduce: reduce,
    mutations: {
      clipsLoaded: true,
      loadFailed: true,
      timeChanged: true,
      filterSelected: true,
      thumbnailStarted: true,
      thumbnailLoaded: true,
      thumbnailFailed: true,
      thumbnailCancelled: true,
      savingStarted: true,
      savingStopped: true,
      menuShown: true,
      menuClosed: true,
      deleteConfirmShown: true,
      deleteConfirmClosed: true,
      searchVisibilityChanged: true,
    },
    start: (scope) => startHomeListeners(scope),
  });
}
