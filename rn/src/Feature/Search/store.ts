import { createScreenStore } from '../../Shared/State/screenStore';
import { initialSearchState, reduceSearch } from './searchState';
import { startSearchListeners } from './listeners';

export function createSearchStore(onReload: () => void) {
  return createScreenStore({
    initialState: () => initialSearchState(Date.now()),
    reduce: reduceSearch,
    mutations: {
      clipsLoaded: true,
      loadFailed: true,
      timeChanged: true,
      filterSelected: true,
      thumbnailStarted: true,
      thumbnailLoaded: true,
      thumbnailFailed: true,
      thumbnailCancelled: true,
      queryChanged: true,
      searchHistoryLoaded: true,
      searchHistoryLoadFailed: true,
    },
    start: (scope) => startSearchListeners(scope, onReload),
  });
}
