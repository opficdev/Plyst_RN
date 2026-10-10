import type { ClipRecord } from 'plyst-bridge';
import type { HomeFilter, HomeLoadPhase } from './homeContent';

export const homeThumbnailLimit = 48;
export type HomeState = {
  loadPhase: HomeLoadPhase;
  clips: ClipRecord[];
  now: number;
  filter: HomeFilter;
  thumbnails: Record<string, string>;
  thumbnailOrder: string[];
  loadingThumbnails: Record<string, true>;
  failedThumbnails: Record<string, true>;
  isSearchVisible: boolean;
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
  };
}
export type HomeAction =
  | { type: 'clipsLoaded'; clips: ClipRecord[]; now: number }
  | { type: 'loadFailed' }
  | { type: 'timeChanged'; now: number }
  | { type: 'filterSelected'; filter: HomeFilter }
  | { type: 'thumbnailStarted'; key: string }
  | { type: 'thumbnailLoaded'; key: string; uri: string }
  | { type: 'thumbnailFailed'; key: string }
  | { type: 'thumbnailCancelled'; key: string }
  | { type: 'searchVisibilityChanged'; isVisible: boolean };

function clipID(key: string): string {
  return key.slice(0, key.lastIndexOf(':'));
}

export function reduce(state: HomeState, action: HomeAction): HomeState {
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
    case 'clipsLoaded': {
      next.clips = action.clips;
      next.now = action.now;
      next.loadPhase = 'loaded';
      const valid = new Set(
        action.clips
          .filter((clip) => clip.image !== null)
          .map((clip) => clip.id),
      );
      const retained = (key: string) => valid.has(clipID(key));
      next.thumbnails = Object.fromEntries(
        Object.entries(next.thumbnails).filter(([key]) => retained(key)),
      );
      next.thumbnailOrder = next.thumbnailOrder.filter(retained);
      next.loadingThumbnails = Object.fromEntries(
        Object.entries(next.loadingThumbnails).filter(([key]) => retained(key)),
      );
      next.failedThumbnails = Object.fromEntries(
        Object.entries(next.failedThumbnails).filter(([key]) => retained(key)),
      );
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
      next.loadingThumbnails[action.key] = true;
      break;
    case 'thumbnailLoaded': {
      const wasLoading = next.loadingThumbnails[action.key];
      delete next.loadingThumbnails[action.key];
      if (
        !wasLoading ||
        !next.clips.some(
          (clip) => clip.id === clipID(action.key) && clip.image !== null,
        )
      )
        break;
      next.thumbnails[action.key] = action.uri;
      next.thumbnailOrder = next.thumbnailOrder.filter(
        (key) => key !== action.key,
      );
      next.thumbnailOrder.push(action.key);
      while (homeThumbnailLimit < next.thumbnailOrder.length) {
        const oldest = next.thumbnailOrder.shift()!;
        delete next.thumbnails[oldest];
      }
      break;
    }
    case 'thumbnailFailed':
      delete next.loadingThumbnails[action.key];
      next.failedThumbnails[action.key] = true;
      break;
    case 'thumbnailCancelled':
      delete next.loadingThumbnails[action.key];
      break;
    case 'searchVisibilityChanged':
      next.isSearchVisible = action.isVisible;
      break;
  }
  return next;
}
