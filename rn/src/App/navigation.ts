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

// clipClosed는 닫기 버튼, 스와이프 dismiss, 저장·삭제 완료 중 먼저 온 것으로 보내며 여러 번 보내도 같습니다.
// detail을 비우면 스택 항목이 빠지면서 시스템이 시트를 dismiss합니다.
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
