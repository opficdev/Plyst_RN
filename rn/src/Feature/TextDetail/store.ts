import { createSliceStore } from '../../Shared/State/screenStore';
import { textDetailSlice } from './draft';
import { startTextDetailListeners } from './listeners';

export function createTextDetailStore(clipID: string) {
  return createSliceStore({
    slice: textDetailSlice,
    start: (listen) => startTextDetailListeners(listen, clipID),
  });
}
