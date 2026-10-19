import { createScreenStore } from '../../Shared/State/screenStore';
import { imageDetailSlice } from './draft';
import { startImageDetailListeners } from './listeners';

export function createImageDetailStore(clipID: string) {
  return createScreenStore({
    slice: imageDetailSlice,
    start: (listen) => startImageDetailListeners(listen, clipID),
  });
}
