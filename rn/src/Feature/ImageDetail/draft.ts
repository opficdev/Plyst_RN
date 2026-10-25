import type { ClipRecord } from '../../Model/clipRecord';
import { equivalent, normalizedName } from '../../Model/clipDetailValues';
import { createSlice } from '../../Shared/State/screenStore';
import type { PayloadAction } from '../../Shared/State/screenStore';

export type Draft = { name: string; isPinned: boolean };

export function draftFromClip(clip: ClipRecord): Draft {
  return {
    name: clip.name ?? '',
    isPinned: clip.pinnedAt !== null,
  };
}

export function differs(draft: Draft, clip: ClipRecord): boolean {
  return (
    !equivalent(normalizedName(draft), clip.name) ||
    draft.isPinned !== (clip.pinnedAt !== null)
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

export type ImageDetailLoaded = { phase: 'loaded' } & ImageDetailState;

// closed는 최초 조회 실패나 조회 전 삭제로 화면이 열리지 못한 경우
export type ImageDetailStoreState =
  { phase: 'loading' } | { phase: 'closed' } | ImageDetailLoaded;

export function loadedState(clip: ClipRecord): ImageDetailLoaded {
  return {
    phase: 'loaded',
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

export function isSaveEnabled(state: ImageDetailStoreState): boolean {
  return state.phase === 'loaded' && canSave(state);
}

export function isClosed(state: ImageDetailStoreState): boolean {
  return (
    state.phase === 'closed' ||
    (state.phase === 'loaded' && (state.isRemoved || state.isSaved))
  );
}

// reducer는 변경 전 상태로 판정함
// listener는 getOriginalState로 같은 조건을 판정함
export function canStartSave(
  state: ImageDetailStoreState,
): state is ImageDetailLoaded {
  return state.phase === 'loaded' && !state.isSaved && canSave(state);
}

export function canStartDelete(
  state: ImageDetailStoreState,
): state is ImageDetailLoaded {
  return state.phase === 'loaded' && !state.isDeleting && !state.isRemoved;
}

export function canStartPhotoSave(
  state: ImageDetailStoreState,
): state is ImageDetailLoaded {
  return (
    state.phase === 'loaded' &&
    !state.isSavingToPhotos &&
    !state.isDeleting &&
    !state.isRemoved
  );
}

export const imageDetailSlice = createSlice({
  name: 'imageDetail',
  initialState: (): ImageDetailStoreState => ({ phase: 'loading' }),
  reducers: {
    viewDidLoad() {},
    copy() {},
    previewRequested() {},
    save(state) {
      if (canStartSave(state)) state.isSaving = true;
    },
    delete(state) {
      if (!canStartDelete(state)) return;
      state.isDeleting = true;
      state.isDeleteSheetOpen = false;
    },
    saveToPhotos(state) {
      if (canStartPhotoSave(state)) state.isSavingToPhotos = true;
    },
    clipLoaded(state, { payload: clip }: PayloadAction<ClipRecord>) {
      if (state.phase === 'closed') return;
      if (state.phase === 'loading') return loadedState(clip);
      if (state.isRemoved || state.isSaved) return;
      const original = draftFromClip(state.clip);
      if (
        equivalent(state.draft.name, original.name) &&
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
      state.isSavingToPhotos = false;
      state.isSaving = false;
      state.isDeleting = false;
      state.isRemoved = true;
      state.isDeleteSheetOpen = false;
    },
    nameChanged(state, { payload: name }: PayloadAction<string>) {
      if (state.phase === 'loaded') state.draft.name = name;
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
    photoSaveFinished(state) {
      if (state.phase === 'loaded') state.isSavingToPhotos = false;
    },
    previewReady(state, { payload: uri }: PayloadAction<string>) {
      if (state.phase === 'loaded' && !state.isRemoved) {
        state.preview.uri = uri;
      }
    },
    previewLoaded(
      state,
      { payload }: PayloadAction<{ width: number; height: number }>,
    ) {
      if (
        state.phase !== 'loaded' ||
        state.isRemoved ||
        state.preview.status === 'failed'
      ) {
        return;
      }
      state.preview.status = 'loaded';
      if (0 < payload.width && 0 < payload.height) {
        state.preview.aspectRatio = payload.width / payload.height;
      }
    },
    previewFailed(state) {
      if (state.phase === 'loaded' && !state.isRemoved) {
        state.preview.status = 'failed';
        state.preview.uri = null;
      }
    },
  },
});

export const imageDetailActions = imageDetailSlice.actions;
