import type { ClipRecord } from '../../Model/clipRecord';
import { original } from '../../Shared/State/screenStore';
import { clipGridActions as actions } from './actions';
import type { ClipFilter } from './filter';
import type { ClipLoadPhase } from './loadPhase';
import { reduceClipThumbnails, retainClipThumbnails } from './thumbnails';
import type { ClipThumbnailAction, ClipThumbnails } from './thumbnails';

export type ClipGridState = ClipThumbnails & {
  loadPhase: ClipLoadPhase;
  clips: ClipRecord[];
  now: number;
  filter: ClipFilter;
};

export function clipGridInitialState(now: number): ClipGridState {
  return {
    loadPhase: 'loading',
    clips: [],
    now,
    filter: 'all',
    thumbnails: {},
    thumbnailOrder: [],
    loadingThumbnails: {},
    failedThumbnails: {},
  };
}

function thumbnailsOf(state: ClipGridState): ClipThumbnails {
  return {
    thumbnails: state.thumbnails,
    thumbnailOrder: state.thumbnailOrder,
    loadingThumbnails: state.loadingThumbnails,
    failedThumbnails: state.failedThumbnails,
  };
}

// clips는 읽기만 하므로 draft 대신 원본 배열을 넘겨 요소마다 draft가 만들어지지 않게 합니다.
function reduceThumbnail(state: ClipGridState, action: ClipThumbnailAction) {
  Object.assign(
    state,
    reduceClipThumbnails(
      thumbnailsOf(state),
      action,
      original(state.clips) ?? state.clips,
    ),
  );
}

type ActionCreatorLike = {
  (...args: never[]): { type: string };
  type: string;
};

// ActionReducerMapBuilder가 화면 State에 묶여 있어 addCase만 가진 최소 형태로 받습니다.
type ClipGridCaseBuilder = {
  addCase<ActionCreator extends ActionCreatorLike>(
    actionCreator: ActionCreator,
    reducer: (state: ClipGridState, action: ReturnType<ActionCreator>) => void,
  ): unknown;
};

// Home과 Search가 extraReducers로 받는 공통 목록 case입니다.
export function addClipGridCases(builder: ClipGridCaseBuilder) {
  builder.addCase(actions.clipsLoaded, (state, { payload }) => {
    Object.assign(
      state,
      retainClipThumbnails(thumbnailsOf(state), payload.clips),
    );
    state.clips = payload.clips;
    state.now = payload.now;
    state.loadPhase = 'loaded';
  });
  builder.addCase(actions.loadFailed, (state) => {
    state.loadPhase = 'failed';
  });
  builder.addCase(actions.timeChanged, (state, { payload }) => {
    state.now = payload;
  });
  builder.addCase(actions.filterSelected, (state, { payload }) => {
    state.filter = payload;
  });
  builder.addCase(actions.thumbnailStarted, (state, { payload: key }) => {
    reduceThumbnail(state, { type: 'thumbnailStarted', key });
  });
  builder.addCase(actions.thumbnailLoaded, (state, { payload }) => {
    reduceThumbnail(state, { type: 'thumbnailLoaded', ...payload });
  });
  builder.addCase(actions.thumbnailFailed, (state, { payload: key }) => {
    reduceThumbnail(state, { type: 'thumbnailFailed', key });
  });
  builder.addCase(actions.thumbnailCancelled, (state, { payload: key }) => {
    reduceThumbnail(state, { type: 'thumbnailCancelled', key });
  });
}
