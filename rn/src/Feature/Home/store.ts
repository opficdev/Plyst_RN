import { createScreenStore } from '../../Shared/State/screenStore';
import { homeSlice } from './state';
import { startHomeListeners } from './listeners';

export function createHomeStore() {
  return createScreenStore({ slice: homeSlice, start: startHomeListeners });
}
