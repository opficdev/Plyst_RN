import { createSliceStore } from '../../Shared/State/screenStore';
import { imageDetailSlice } from './draft';
import { startImageDetailListeners } from './listeners';

export function createImageDetailStore(clipID: string) {
  return createSliceStore({
    slice: imageDetailSlice,
    start: (listen) => startImageDetailListeners(listen, clipID),
  });
}
