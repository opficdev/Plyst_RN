import {
  reduceClipThumbnails,
  retainClipThumbnails,
} from '../ClipGrid/clipThumbnails';
import type {
  ClipThumbnailAction,
  ClipThumbnails,
} from '../ClipGrid/clipThumbnails';
import type { ClipRecord } from 'plyst-bridge';
import type { ClipFilter } from '../ClipGrid/clipFilter';
import type { ClipLoadPhase } from '../ClipGrid/clipLoadPhase';

export type HomeState = ClipThumbnails & {
  loadPhase: ClipLoadPhase;
  clips: ClipRecord[];
  now: number;
  filter: ClipFilter;
  isSearchVisible: boolean;
  isSaving: boolean;
  menuClip: ClipRecord | null;
  isMenuVisible: boolean;
  isDeleteConfirmVisible: boolean;
};
export function initialState(now: number): HomeState {
  return {
    loadPhase: 'loading',
    clips: [],
    now,
    filter: 'all',
    thumbnails: {},
    thumbnailOrder: [],
    loadingThumbnails: {},
    failedThumbnails: {},
    isSearchVisible: false,
    isSaving: false,
    menuClip: null,
    isMenuVisible: false,
    isDeleteConfirmVisible: false,
  };
}
export type HomeAction =
  | { type: 'savingStarted' }
  | { type: 'savingStopped' }
  | { type: 'menuShown'; clip: ClipRecord }
  | { type: 'menuClosed' }
  | { type: 'deleteConfirmShown'; clip: ClipRecord }
  | { type: 'deleteConfirmClosed' }
  | { type: 'clipsLoaded'; clips: ClipRecord[]; now: number }
  | { type: 'loadFailed' }
  | { type: 'timeChanged'; now: number }
  | { type: 'filterSelected'; filter: ClipFilter }
  | ClipThumbnailAction
  | { type: 'searchVisibilityChanged'; isVisible: boolean };

export function reduce(state: HomeState, action: HomeAction): HomeState {
  if (
    action.type === 'menuShown' &&
    (state.isMenuVisible || state.isDeleteConfirmVisible)
  )
    return state;
  if (action.type === 'filterSelected' && state.filter === action.filter)
    return state;
  const next = {
    ...state,
    thumbnails: { ...state.thumbnails },
    thumbnailOrder: [...state.thumbnailOrder],
    loadingThumbnails: { ...state.loadingThumbnails },
    failedThumbnails: { ...state.failedThumbnails },
  };
  switch (action.type) {
    case 'savingStarted':
      next.isSaving = true;
      break;
    case 'savingStopped':
      next.isSaving = false;
      break;
    case 'menuShown':
      next.menuClip = action.clip;
      next.isMenuVisible = true;
      break;
    case 'menuClosed':
      next.isMenuVisible = false;
      break;
    case 'deleteConfirmShown':
      next.menuClip = action.clip;
      next.isDeleteConfirmVisible = true;
      break;
    case 'deleteConfirmClosed':
      next.isDeleteConfirmVisible = false;
      break;
    case 'clipsLoaded': {
      next.clips = action.clips;
      next.now = action.now;
      next.loadPhase = 'loaded';
      Object.assign(next, retainClipThumbnails(next, action.clips));
      break;
    }
    case 'loadFailed':
      next.loadPhase = 'failed';
      break;
    case 'timeChanged':
      next.now = action.now;
      break;
    case 'filterSelected':
      next.filter = action.filter;
      break;
    case 'thumbnailStarted':
    case 'thumbnailLoaded':
    case 'thumbnailFailed':
    case 'thumbnailCancelled':
      Object.assign(next, reduceClipThumbnails(next, action, next.clips));
      break;
    case 'searchVisibilityChanged':
      next.isSearchVisible = action.isVisible;
      break;
  }
  return next;
}
