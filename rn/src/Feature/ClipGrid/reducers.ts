import type { ClipRecord } from '../../Model/clipRecord';
import { original } from '../../Shared/State/screenStore';
import type {
  CaseReducerActions,
  PayloadAction,
} from '../../Shared/State/screenStore';
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

type ThumbnailRequest = { id: string; pixels: number };

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

// Home과 Search가 각자의 slice reducers에 펼쳐 쓰는 공통 case reducer입니다.
// action 생성자는 이 객체를 받은 slice가 자기 이름으로 만듭니다.
export const clipGridReducers = {
  clipsLoaded(
    state: ClipGridState,
    { payload }: PayloadAction<{ clips: ClipRecord[]; now: number }>,
  ) {
    Object.assign(
      state,
      retainClipThumbnails(thumbnailsOf(state), payload.clips),
    );
    state.clips = payload.clips;
    state.now = payload.now;
    state.loadPhase = 'loaded';
  },
  loadFailed(state: ClipGridState) {
    state.loadPhase = 'failed';
  },
  timeChanged(state: ClipGridState, { payload }: PayloadAction<number>) {
    state.now = payload;
  },
  filterSelected(state: ClipGridState, { payload }: PayloadAction<ClipFilter>) {
    state.filter = payload;
  },
  thumbnailStarted(
    state: ClipGridState,
    { payload: key }: PayloadAction<string>,
  ) {
    reduceThumbnail(state, { type: 'thumbnailStarted', key });
  },
  thumbnailLoaded(
    state: ClipGridState,
    { payload }: PayloadAction<{ key: string; uri: string }>,
  ) {
    reduceThumbnail(state, { type: 'thumbnailLoaded', ...payload });
  },
  thumbnailFailed(
    state: ClipGridState,
    { payload: key }: PayloadAction<string>,
  ) {
    reduceThumbnail(state, { type: 'thumbnailFailed', key });
  },
  thumbnailCancelled(
    state: ClipGridState,
    { payload: key }: PayloadAction<string>,
  ) {
    reduceThumbnail(state, { type: 'thumbnailCancelled', key });
  },
  // 아래 둘은 listener만 처리하는 효과용 action입니다.
  thumbnailRequested: {
    reducer() {},
    prepare: (request: ThumbnailRequest) => ({ payload: request }),
  },
  thumbnailCancelRequested: {
    reducer() {},
    prepare: (request: ThumbnailRequest) => ({ payload: request }),
  },
};

// 공통 로직이 slice마다 다른 action 생성자를 받을 때 쓰는 형태입니다.
export type ClipGridActions = CaseReducerActions<
  typeof clipGridReducers,
  string
>;
