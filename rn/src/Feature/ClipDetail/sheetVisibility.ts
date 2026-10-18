export type SheetVisibility = {
  // Modal의 present가 끝났음을 뜻합니다. onShow 전에는 dismiss를 요청하지 않습니다.
  isShown: boolean;
  isCloseRequested: boolean;
  // 사용자가 스와이프로 이미 닫았음을 뜻합니다. 이때 visible을 바꾸면 닫힌 VC에 dismiss가 다시 갑니다.
  isSwiped: boolean;
};

export type SheetVisibilityAction = 'shown' | 'closeRequested' | 'swiped';

export const initialSheetVisibility: SheetVisibility = {
  isShown: false,
  isCloseRequested: false,
  isSwiped: false,
};

export function reduceSheetVisibility(
  state: SheetVisibility,
  action: SheetVisibilityAction,
): SheetVisibility {
  switch (action) {
    case 'shown':
      return state.isShown ? state : { ...state, isShown: true };
    case 'closeRequested':
      return state.isCloseRequested
        ? state
        : { ...state, isCloseRequested: true };
    case 'swiped':
      return state.isSwiped ? state : { ...state, isSwiped: true };
  }
}

// 닫기 요청이 present 중에 오면 onShow가 올 때까지 visible을 유지합니다.
export function isSheetVisible(state: SheetVisibility, isClosed: boolean) {
  return (
    state.isSwiped || !(state.isShown && (state.isCloseRequested || isClosed))
  );
}
