import type { ClipRecord } from 'plyst-bridge';
import { equivalent, normalizedName } from './clipDetailValues';

export type Draft = { name: string; isPinned: boolean };

export function draftFromClip(clip: ClipRecord): Draft {
  return {
    name: clip.name ?? '',
    isPinned: clip.isPinned,
  };
}

export function differs(draft: Draft, clip: ClipRecord): boolean {
  return (
    !equivalent(normalizedName(draft), clip.name) ||
    draft.isPinned !== clip.isPinned
  );
}

export type Preview = {
  status: 'loading' | 'loaded' | 'failed';
  uri: string | null;
  aspectRatio: number;
};

export type ImageDetailState = {
  clip: ClipRecord;
  draft: Draft;
  isSavingToPhotos: boolean;
  preview: Preview;
  isSaving: boolean;
  isDeleting: boolean;
  isRemoved: boolean;
  isSaved: boolean;
  isDeleteSheetOpen: boolean;
};

export function initialState(clip: ClipRecord): ImageDetailState {
  return {
    clip,
    draft: draftFromClip(clip),
    isSavingToPhotos: false,
    preview: { status: 'loading', uri: null, aspectRatio: 4 / 3 },
    isSaving: false,
    isDeleting: false,
    isRemoved: false,
    isSaved: false,
    isDeleteSheetOpen: false,
  };
}

export function hasChanges(state: ImageDetailState): boolean {
  return differs(state.draft, state.clip);
}

export function canSave(state: ImageDetailState): boolean {
  return (
    hasChanges(state) &&
    !state.isSaving &&
    !state.isDeleting &&
    !state.isRemoved
  );
}

export type ImageDetailAction =
  | { type: 'clipLoaded'; clip: ClipRecord }
  | { type: 'removed' }
  | { type: 'nameChanged'; name: string }
  | { type: 'pinnedChanged'; isPinned: boolean }
  | { type: 'saveStarted' }
  | { type: 'saved'; clip: ClipRecord }
  | { type: 'saveFailed' }
  | { type: 'deleteSheetShown' }
  | { type: 'deleteSheetClosed' }
  | { type: 'deleteStarted' }
  | { type: 'deleteFailed' }
  | { type: 'photoSaveStarted' }
  | { type: 'photoSaveFinished' }
  | { type: 'previewReady'; uri: string }
  | { type: 'previewLoaded'; width: number; height: number }
  | { type: 'previewFailed' };

export function reduce(
  state: ImageDetailState,
  action: ImageDetailAction,
): ImageDetailState {
  const next = { ...state, draft: { ...state.draft } };
  switch (action.type) {
    case 'clipLoaded': {
      const original = draftFromClip(state.clip);
      if (
        equivalent(state.draft.name, original.name) &&
        state.draft.isPinned === original.isPinned
      ) {
        next.draft = draftFromClip(action.clip);
      }
      next.clip = action.clip;
      break;
    }
    case 'removed':
      next.isSavingToPhotos = false;
      next.isSaving = false;
      next.isDeleting = false;
      next.isRemoved = true;
      next.isDeleteSheetOpen = false;
      break;
    case 'nameChanged':
      next.draft.name = action.name;
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
    case 'photoSaveStarted':
      next.isSavingToPhotos = true;
      break;
    case 'photoSaveFinished':
      next.isSavingToPhotos = false;
      break;
    case 'previewReady':
      if (!state.isRemoved) {
        next.preview = { ...state.preview, uri: action.uri };
      }
      break;
    case 'previewLoaded':
      if (!state.isRemoved && state.preview.status !== 'failed') {
        next.preview = {
          ...state.preview,
          status: 'loaded',
          aspectRatio:
            0 < action.width && 0 < action.height
              ? action.width / action.height
              : state.preview.aspectRatio,
        };
      }
      break;
    case 'previewFailed':
      if (!state.isRemoved) {
        next.preview = { ...state.preview, status: 'failed', uri: null };
      }
      break;
    case 'deleteFailed':
      next.isDeleting = false;
      break;
  }
  return next;
}
