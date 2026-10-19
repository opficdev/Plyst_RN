import { createSliceStore } from '../../Shared/State/screenStore';
import { homeSlice } from './state';
import { startHomeListeners } from './listeners';

export function createHomeStore() {
  return createSliceStore({ slice: homeSlice, start: startHomeListeners });
}
