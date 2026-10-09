import type { ClipRecord } from 'plyst-bridge';
import { equivalent, normalizedMemo, normalizedName } from './clipDetailValues';

export type Draft = { name: string; memo: string; isPinned: boolean };

export function draftFromClip(clip: ClipRecord): Draft {
  return {
    name: clip.name ?? '',
    memo: clip.memo ?? '',
    isPinned: clip.isPinned,
  };
}

export function differs(draft: Draft, clip: ClipRecord): boolean {
  return (
    !equivalent(normalizedName(draft), clip.name) ||
    !equivalent(normalizedMemo(draft), clip.memo) ||
    draft.isPinned !== clip.isPinned
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

export function initialState(clip: ClipRecord): TextDetailState {
  return {
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

export type TextDetailAction =
  | { type: 'clipLoaded'; clip: ClipRecord }
  | { type: 'removed' }
  | { type: 'nameChanged'; name: string }
  | { type: 'memoChanged'; memo: string }
  | { type: 'pinnedChanged'; isPinned: boolean }
  | { type: 'saveStarted' }
  | { type: 'saved'; clip: ClipRecord }
  | { type: 'saveFailed' }
  | { type: 'deleteSheetShown' }
  | { type: 'deleteSheetClosed' }
  | { type: 'deleteStarted' }
  | { type: 'deleteFailed' };

export function reduce(
  state: TextDetailState,
  action: TextDetailAction,
): TextDetailState {
  const next = { ...state, draft: { ...state.draft } };
  switch (action.type) {
    case 'clipLoaded': {
      const original = draftFromClip(state.clip);
      if (
        state.draft.name === original.name &&
        state.draft.memo === original.memo &&
        state.draft.isPinned === original.isPinned
      ) {
        next.draft = draftFromClip(action.clip);
      }
      next.clip = action.clip;
      break;
    }
    case 'removed':
      next.isSaving = false;
      next.isDeleting = false;
      next.isRemoved = true;
      next.isDeleteSheetOpen = false;
      break;
    case 'nameChanged':
      next.draft.name = action.name;
      break;
    case 'memoChanged':
      next.draft.memo = action.memo;
      break;
    case 'pinnedChanged':
      next.draft.isPinned = action.isPinned;
      break;
    case 'saveStarted':
      next.isSaving = true;
      break;
    case 'saved':
      next.isSaving = false;
      next.isSaved = true;
      next.clip = action.clip;
      if (!differs(state.draft, action.clip)) {
        next.draft = draftFromClip(action.clip);
      }
      break;
    case 'saveFailed':
      next.isSaving = false;
      break;
    case 'deleteSheetShown':
      next.isDeleteSheetOpen = true;
      break;
    case 'deleteSheetClosed':
      next.isDeleteSheetOpen = false;
      break;
    case 'deleteStarted':
      next.isDeleting = true;
      next.isDeleteSheetOpen = false;
      break;
    case 'deleteFailed':
      next.isDeleting = false;
      break;
  }
  return next;
}
