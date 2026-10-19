import { createSlice } from '../../Shared/State/screenStore';
import type { PayloadAction } from '../../Shared/State/screenStore';
import { clipGridInitialState, clipGridReducers } from '../ClipGrid/reducers';
import type { ClipGridState } from '../ClipGrid/reducers';

export type SearchState = ClipGridState & {
  query: string;
  searchHistory: string[];
  searchHistoryPhase: 'initial' | 'loaded' | 'failed';
};

export function initialSearchState(now: number): SearchState {
  return {
    ...clipGridInitialState(now),
    query: '',
    searchHistory: [],
    searchHistoryPhase: 'initial',
  };
}

export const searchSlice = createSlice({
  name: 'search',
  initialState: (): SearchState => initialSearchState(Date.now()),
  reducers: {
    ...clipGridReducers,
    viewDidLoad() {},
    submitQuery() {},
    clearRecentTerms() {},
    removeRecentTerm: {
      reducer() {},
      prepare: (term: string) => ({ payload: term }),
    },
    copy: {
      reducer() {},
      prepare: (id: string) => ({ payload: id }),
    },
    queryChanged(state, { payload: query }: PayloadAction<string>) {
      state.query = query;
    },
    searchHistoryLoaded(state, { payload: terms }: PayloadAction<string[]>) {
      state.searchHistory = terms;
      state.searchHistoryPhase = 'loaded';
    },
    searchHistoryLoadFailed(state) {
      state.searchHistoryPhase = 'failed';
    },
  },
});

export const searchActions = searchSlice.actions;
