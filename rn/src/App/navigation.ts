import type { ClipKind } from '../Model/clipRecord';
import { createSlice } from '../Shared/State/screenStore';
import type { PayloadAction } from '../Shared/State/screenStore';

export type AppDetail = { clipID: string; kind: ClipKind };

export type AppNavigation = {
  isSearchVisible: boolean;
  detail: AppDetail | null;
};

export function initialNavigation(): AppNavigation {
  return { isSearchVisible: false, detail: null };
}

// clipClosed는 시트의 dismiss가 끝난 뒤에만 보냅니다.
// 시트 present가 실패하면 detail이 남아 앱을 다시 시작할 때까지 상세와 검색이 열리지 않는 한계가 있습니다.
export const navigationSlice = createSlice({
  name: 'navigation',
  initialState: initialNavigation,
  reducers: {
    searchOpened(state) {
      // 상세가 열려 있거나 검색이 이미 열려 있으면 열지 않습니다.
      if (!state.isSearchVisible && state.detail === null) {
        state.isSearchVisible = true;
      }
    },
    searchClosed(state) {
      state.isSearchVisible = false;
    },
    clipOpened(state, { payload: detail }: PayloadAction<AppDetail>) {
      // 상세가 열려 있거나 닫히는 중이면 다시 열지 않습니다.
      if (state.detail === null) state.detail = detail;
    },
    clipClosed(state) {
      state.detail = null;
    },
  },
});

export const navigationActions = navigationSlice.actions;
