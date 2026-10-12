import type { ClipRecord } from 'plyst-bridge';
import type { ClipFilter } from '../ClipGrid/filter';
import type { ClipLoadPhase } from '../ClipGrid/loadPhase';
import type {
  ClipThumbnailAction,
  ClipThumbnails,
} from '../ClipGrid/thumbnails';
import {
  reduceClipThumbnails,
  retainClipThumbnails,
} from '../ClipGrid/thumbnails';

export type SearchState = ClipThumbnails & {
  loadPhase: ClipLoadPhase;
  clips: ClipRecord[];
  now: number;
  query: string;
  filter: ClipFilter;
  searchHistory: string[];
  searchHistoryPhase: 'initial' | 'loaded' | 'failed';
};

export function initialSearchState(now: number): SearchState {
  return {
    loadPhase: 'loading',
    clips: [],
    now,
    query: '',
    filter: 'all',
    searchHistory: [],
    searchHistoryPhase: 'initial',
    thumbnails: {},
    thumbnailOrder: [],
    loadingThumbnails: {},
    failedThumbnails: {},
  };
}

export type SearchAction =
  | { type: 'clipsLoaded'; clips: ClipRecord[]; now: number }
  | { type: 'loadFailed' }
  | { type: 'timeChanged'; now: number }
  | { type: 'queryChanged'; query: string }
  | { type: 'filterSelected'; filter: ClipFilter }
  | { type: 'searchHistoryLoaded'; terms: string[] }
  | { type: 'searchHistoryLoadFailed' }
  | ClipThumbnailAction;

export function reduceSearch(
  state: SearchState,
  action: SearchAction,
): SearchState {
  switch (action.type) {
    case 'clipsLoaded':
      return {
        ...state,
        ...retainClipThumbnails(state, action.clips),
        clips: action.clips,
        now: action.now,
        loadPhase: 'loaded',
      };
    case 'loadFailed':
      return { ...state, loadPhase: 'failed' };
    case 'timeChanged':
      return { ...state, now: action.now };
    case 'queryChanged':
      return { ...state, query: action.query };
    case 'filterSelected':
      return state.filter === action.filter
        ? state
        : { ...state, filter: action.filter };
    case 'searchHistoryLoaded':
      return {
        ...state,
        searchHistory: action.terms,
        searchHistoryPhase: 'loaded',
      };
    case 'searchHistoryLoadFailed':
      return { ...state, searchHistoryPhase: 'failed' };
    default:
      return { ...state, ...reduceClipThumbnails(state, action, state.clips) };
  }
}
