import type { ClipRecord } from '../../Model/clipRecord';
import { createSlice } from '../../Shared/State/screenStore';
import type { PayloadAction } from '../../Shared/State/screenStore';
import { addClipGridCases, clipGridInitialState } from '../ClipGrid/reducers';
import type { ClipGridState } from '../ClipGrid/reducers';

export type HomeState = ClipGridState & {
  isSaving: boolean;
  menuClip: ClipRecord | null;
  isMenuVisible: boolean;
  isDeleteConfirmVisible: boolean;
};

export function initialHomeState(now: number): HomeState {
  return {
    ...clipGridInitialState(now),
    isSaving: false,
    menuClip: null,
    isMenuVisible: false,
    isDeleteConfirmVisible: false,
  };
}

export const homeSlice = createSlice({
  name: 'home',
  initialState: (): HomeState => initialHomeState(Date.now()),
  reducers: {
    viewDidLoad() {},
    setPinned() {},
    delete() {},
    copy: {
      reducer() {},
      prepare: (id: string) => ({ payload: id }),
    },
    saveCurrentClipboard(state) {
      state.isSaving = true;
    },
    savingStopped(state) {
      state.isSaving = false;
    },
    menuShown(state, { payload: clip }: PayloadAction<ClipRecord>) {
      if (state.isMenuVisible || state.isDeleteConfirmVisible) return;
      state.menuClip = clip;
      state.isMenuVisible = true;
    },
    menuClosed(state) {
      state.isMenuVisible = false;
    },
    deleteConfirmShown(state, { payload: clip }: PayloadAction<ClipRecord>) {
      state.menuClip = clip;
      state.isDeleteConfirmVisible = true;
    },
    deleteConfirmClosed(state) {
      state.isDeleteConfirmVisible = false;
    },
  },
  extraReducers: (builder) => addClipGridCases(builder),
});

export const homeActions = homeSlice.actions;
