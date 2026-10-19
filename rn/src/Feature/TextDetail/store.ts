import { createScreenStore } from '../../Shared/State/screenStore';
import { textDetailSlice } from './draft';
import { startTextDetailListeners } from './listeners';

export function createTextDetailStore(clipID: string) {
  return createScreenStore({
    slice: textDetailSlice,
    start: (listen) => startTextDetailListeners(listen, clipID),
  });
}
