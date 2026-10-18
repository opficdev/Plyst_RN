import type { ClipKind } from '../Model/clipRecord';

export type AppDetail = { clipID: string; kind: ClipKind };

export type AppNavigation = {
  isSearchVisible: boolean;
  detail: AppDetail | null;
};

export type AppNavigationAction =
  | { type: 'searchOpened' }
  | { type: 'searchClosed' }
  | { type: 'clipOpened'; detail: AppDetail }
  | { type: 'clipClosed' };

export function initialNavigation(): AppNavigation {
  return { isSearchVisible: false, detail: null };
}

// clipClosed는 시트의 dismiss가 끝난 뒤에만 보냅니다.
// 시트 present가 실패하면 detail이 남아 앱을 다시 시작할 때까지 상세와 검색이 열리지 않는 한계가 있습니다.
export function reduceNavigation(
  state: AppNavigation,
  action: AppNavigationAction,
): AppNavigation {
  switch (action.type) {
    case 'searchOpened':
      // 상세가 열려 있거나 검색이 이미 열려 있으면 열지 않습니다.
      return state.isSearchVisible || state.detail !== null
        ? state
        : { ...state, isSearchVisible: true };
    case 'searchClosed':
      return state.isSearchVisible
        ? { ...state, isSearchVisible: false }
        : state;
    case 'clipOpened':
      // 상세가 열려 있거나 닫히는 중이면 다시 열지 않습니다.
      return state.detail !== null
        ? state
        : { ...state, detail: action.detail };
    case 'clipClosed':
      return state.detail === null ? state : { ...state, detail: null };
  }
}
