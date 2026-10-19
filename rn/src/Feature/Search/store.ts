import { createSliceStore } from '../../Shared/State/screenStore';
import { searchSlice } from './state';
import { startSearchListeners } from './listeners';

export function createSearchStore(onReload: () => void) {
  return createSliceStore({
    slice: searchSlice,
    start: (listen, dispatch) =>
      startSearchListeners(listen, dispatch, onReload),
  });
}
