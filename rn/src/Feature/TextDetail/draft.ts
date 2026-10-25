import type { ClipRecord } from '../../Model/clipRecord';
import { createSlice } from '../../Shared/State/screenStore';
import type { PayloadAction } from '../../Shared/State/screenStore';
import {
  equivalent,
  normalizedMemo,
  normalizedName,
} from '../../Model/clipDetailValues';

export type Draft = { name: string; memo: string; isPinned: boolean };

export function draftFromClip(clip: ClipRecord): Draft {
  return {
    name: clip.name ?? '',
    memo: clip.memo ?? '',
    isPinned: clip.pinnedAt !== null,
  };
}

export function differs(draft: Draft, clip: ClipRecord): boolean {
  return (
    !equivalent(normalizedName(draft), clip.name) ||
    !equivalent(normalizedMemo(draft), clip.memo) ||
    draft.isPinned !== (clip.pinnedAt !== null)
  );
}

export type TextDetailState = {
  clip: ClipRecord;
  draft: Draft;
  isSaving: boolean;
  isDeleting: boolean;
  isRemoved: boolean;
  isSaved: boolean;
  isDeleteSheetOpen: boolean;
};

export type TextDetailLoaded = { phase: 'loaded' } & TextDetailState;

// closed는 최초 조회 실패나 조회 전 삭제로 화면이 열리지 못한 경우
export type TextDetailStoreState =
  { phase: 'loading' } | { phase: 'closed' } | TextDetailLoaded;

export function loadedState(clip: ClipRecord): TextDetailLoaded {
  return {
    phase: 'loaded',
    clip,
    draft: draftFromClip(clip),
    isSaving: false,
    isDeleting: false,
    isRemoved: false,
    isSaved: false,
    isDeleteSheetOpen: false,
  };
}

export function hasChanges(state: TextDetailState): boolean {
  return differs(state.draft, state.clip);
}

export function canSave(state: TextDetailState): boolean {
  return (
    hasChanges(state) &&
    !state.isSaving &&
    !state.isDeleting &&
    !state.isRemoved
  );
}

export function isSaveEnabled(state: TextDetailStoreState): boolean {
  return state.phase === 'loaded' && canSave(state);
}

export function isClosed(state: TextDetailStoreState): boolean {
  return (
    state.phase === 'closed' ||
    (state.phase === 'loaded' && (state.isRemoved || state.isSaved))
  );
}

// reducer는 변경 전 상태로 판정함
// listener는 getOriginalState로 같은 조건을 판정함
export function canStartSave(
  state: TextDetailStoreState,
): state is TextDetailLoaded {
  return state.phase === 'loaded' && !state.isSaved && canSave(state);
}

export function canStartDelete(
  state: TextDetailStoreState,
): state is TextDetailLoaded {
  return state.phase === 'loaded' && !state.isDeleting && !state.isRemoved;
}

export const textDetailSlice = createSlice({
  name: 'textDetail',
  initialState: (): TextDetailStoreState => ({ phase: 'loading' }),
  reducers: {
    viewDidLoad() {},
    copy() {},
    save(state) {
      if (canStartSave(state)) state.isSaving = true;
    },
    delete(state) {
      if (!canStartDelete(state)) return;
      state.isDeleting = true;
      state.isDeleteSheetOpen = false;
    },
    clipLoaded(state, { payload: clip }: PayloadAction<ClipRecord>) {
      if (state.phase === 'closed') return;
      if (state.phase === 'loading') return loadedState(clip);
      if (state.isRemoved || state.isSaved) return;
      const original = draftFromClip(state.clip);
      if (
        state.draft.name === original.name &&
        state.draft.memo === original.memo &&
        state.draft.isPinned === original.isPinned
      ) {
        state.draft = draftFromClip(clip);
      }
      state.clip = clip;
    },
    loadFailed(state) {
      if (state.phase === 'loading') return { phase: 'closed' };
    },
    removed(state) {
      if (state.phase === 'loading') return { phase: 'closed' };
      if (state.phase === 'closed') return;
      state.isSaving = false;
      state.isDeleting = false;
      state.isRemoved = true;
      state.isDeleteSheetOpen = false;
    },
    nameChanged(state, { payload: name }: PayloadAction<string>) {
      if (state.phase === 'loaded') state.draft.name = name;
    },
    memoChanged(state, { payload: memo }: PayloadAction<string>) {
      if (state.phase === 'loaded') state.draft.memo = memo;
    },
    pinnedChanged(state, { payload: isPinned }: PayloadAction<boolean>) {
      if (state.phase === 'loaded') state.draft.isPinned = isPinned;
    },
    saved(state, { payload: clip }: PayloadAction<ClipRecord>) {
      if (state.phase !== 'loaded') return;
      state.isSaving = false;
      state.isSaved = true;
      state.clip = clip;
      if (!differs(state.draft, clip)) state.draft = draftFromClip(clip);
    },
    saveFailed(state) {
      if (state.phase === 'loaded') state.isSaving = false;
    },
    deleteSheetShown(state) {
      if (state.phase === 'loaded') state.isDeleteSheetOpen = true;
    },
    deleteSheetClosed(state) {
      if (state.phase === 'loaded') state.isDeleteSheetOpen = false;
    },
    deleteFailed(state) {
      if (state.phase === 'loaded') state.isDeleting = false;
    },
  },
});

export const textDetailActions = textDetailSlice.actions;
