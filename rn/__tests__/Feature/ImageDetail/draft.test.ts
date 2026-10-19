import type { ClipRecord } from '../../../src/Model/clipRecord';
import {
  canSave,
  canStartDelete,
  canStartPhotoSave,
  canStartSave,
  differs,
  draftFromClip,
  imageDetailActions as actions,
  imageDetailSlice,
  isClosed,
  isSaveEnabled,
  loadedState,
} from '../../../src/Feature/ImageDetail/draft';
import type {
  ImageDetailLoaded,
  ImageDetailStoreState,
} from '../../../src/Feature/ImageDetail/draft';

const clip: ClipRecord = {
  id: 'id',
  text: null,
  characterCount: 0,
  textPrefix: null,
  isWebLink: false,
  image: {
    contentType: 'public.png',
    pixelWidth: 2,
    pixelHeight: 3,
    byteCount: 100,
  },
  name: null,
  memo: '보존할 메모',
  pinnedAt: null,
  createdAt: 1000,
  lastUsedAt: null,
};

type Action = Parameters<typeof imageDetailSlice.reducer>[1];

function reduce(state: ImageDetailStoreState, action: Action) {
  return imageDetailSlice.reducer(state, action);
}
function reduceLoaded(state: ImageDetailLoaded, action: Action) {
  return reduce(state, action) as ImageDetailLoaded;
}

const loading = { phase: 'loading' } as const;
const closed = { phase: 'closed' } as const;

test('초기 상태는 조회 전이다', () => {
  expect(imageDetailSlice.getInitialState()).toEqual(loading);
});

test('조회된 초안은 이름과 고정만 가지고 미리보기는 로딩 중이다', () => {
  const state = loadedState(clip);
  expect(state.phase).toBe('loaded');
  expect(state.draft).toEqual({ name: '', isPinned: false });
  expect(state.preview).toEqual({
    status: 'loading',
    uri: null,
    aspectRatio: 4 / 3,
  });
  expect(canSave(state)).toBe(false);
  expect(state.isSavingToPhotos).toBe(false);
});

test('이름의 공백과 정준 동등성을 반영하고 메모 변경은 비교하지 않는다', () => {
  const original = { ...clip, name: 'é' };
  expect(differs({ name: ' e\u0301\n', isPinned: false }, original)).toBe(
    false,
  );
  expect(differs({ name: ' \t\n', isPinned: false }, clip)).toBe(false);
  expect(differs({ name: '', isPinned: false }, { ...clip, name: '' })).toBe(
    true,
  );
  expect(differs({ name: '', isPinned: true }, clip)).toBe(true);
  expect(differs(draftFromClip(clip), { ...clip, memo: '새 메모' })).toBe(
    false,
  );
});

test.each(['isSaving', 'isDeleting', 'isRemoved'] as const)(
  '%s이면 저장을 막는다',
  (flag) => {
    const state = reduceLoaded(loadedState(clip), actions.nameChanged('편집'));
    expect(canSave(state)).toBe(true);
    expect(canSave({ ...state, [flag]: true })).toBe(false);
    expect(canSave({ ...state, isSavingToPhotos: true })).toBe(true);
  },
);

test('저장 버튼은 저장 뒤에도 켜져 있지만 저장 시작은 막는다', () => {
  const state = reduceLoaded(loadedState(clip), actions.nameChanged('편집'));
  expect(isSaveEnabled(state)).toBe(true);
  expect(canStartSave(state)).toBe(true);
  const saved = { ...state, isSaved: true };
  expect(isSaveEnabled(saved)).toBe(true);
  expect(canStartSave(saved)).toBe(false);
  expect(isSaveEnabled(loading)).toBe(false);
  expect(canStartSave(closed)).toBe(false);
});

test.each(['isDeleting', 'isRemoved'] as const)(
  '%s이면 삭제를 시작할 수 없다',
  (flag) => {
    const state = loadedState(clip);
    expect(canStartDelete(state)).toBe(true);
    expect(canStartDelete({ ...state, [flag]: true })).toBe(false);
    expect(canStartDelete(loading)).toBe(false);
  },
);

test.each(['isSavingToPhotos', 'isDeleting', 'isRemoved'] as const)(
  '%s이면 사진 저장을 시작할 수 없다',
  (flag) => {
    const state = loadedState(clip);
    expect(canStartPhotoSave(state)).toBe(true);
    expect(canStartPhotoSave({ ...state, [flag]: true })).toBe(false);
    expect(canStartPhotoSave({ ...state, isSaved: true })).toBe(true);
    expect(canStartPhotoSave(loading)).toBe(false);
  },
);

test('닫힘은 조회 실패나 삭제 또는 저장 완료로 판정한다', () => {
  const state = loadedState(clip);
  expect(isClosed(loading)).toBe(false);
  expect(isClosed(closed)).toBe(true);
  expect(isClosed(state)).toBe(false);
  expect(isClosed({ ...state, isRemoved: true })).toBe(true);
  expect(isClosed({ ...state, isSaved: true })).toBe(true);
});

test('조회 전에는 편집과 시작 action과 미리보기가 상태를 바꾸지 않는다', () => {
  for (const action of [
    actions.nameChanged('이름'),
    actions.pinnedChanged(true),
    actions.save(),
    actions.delete(),
    actions.saveToPhotos(),
    actions.saved(clip),
    actions.saveFailed(),
    actions.deleteSheetShown(),
    actions.deleteSheetClosed(),
    actions.deleteFailed(),
    actions.photoSaveFinished(),
    actions.previewReady('file:///preview'),
    actions.previewLoaded({ width: 3, height: 2 }),
    actions.previewFailed(),
  ]) {
    expect(reduce(loading, action)).toEqual(loading);
  }
});

test('조회 전 clipLoaded는 조회된 상태가 되고 removed와 loadFailed는 화면을 닫는다', () => {
  expect(reduce(loading, actions.clipLoaded(clip))).toEqual(loadedState(clip));
  expect(reduce(loading, actions.removed())).toEqual(closed);
  expect(reduce(loading, actions.loadFailed())).toEqual(closed);
});

test('닫힌 상태는 어떤 action에도 바뀌지 않는다', () => {
  for (const action of [
    actions.clipLoaded(clip),
    actions.removed(),
    actions.loadFailed(),
    actions.nameChanged('이름'),
    actions.save(),
  ]) {
    expect(reduce(closed, action)).toEqual(closed);
  }
});

test('조회된 뒤의 loadFailed는 상태를 바꾸지 않는다', () => {
  const state = loadedState(clip);
  expect(reduceLoaded(state, actions.loadFailed())).toEqual(state);
});

test.each(['isRemoved', 'isSaved'] as const)(
  'clipLoaded는 %s인 상태를 바꾸지 않는다',
  (flag) => {
    const state = { ...loadedState(clip), [flag]: true };
    expect(reduceLoaded(state, actions.clipLoaded(clip))).toEqual(state);
  },
);

test('외부 변경은 편집하지 않은 초안만 갱신하고 미리보기는 유지한다', () => {
  const state = reduceLoaded(
    loadedState(clip),
    actions.previewReady('file:///preview'),
  );
  const updated = { ...clip, name: '외부 이름', pinnedAt: 1000 };
  const loaded = reduceLoaded(state, actions.clipLoaded(updated));
  expect(loaded.draft).toEqual(draftFromClip(updated));
  expect(loaded.preview).toEqual(state.preview);
  const edited = reduceLoaded(state, actions.nameChanged('내 이름'));
  const refreshed = reduceLoaded(edited, actions.clipLoaded(updated));
  expect(refreshed.draft).toEqual(edited.draft);
  expect(refreshed.clip).toEqual(updated);
});

test('초안 비교는 Swift 문자열처럼 정준 동등성을 적용한다', () => {
  const state = loadedState({ ...clip, name: 'é' });
  state.draft.name = 'e\u0301';
  expect(reduceLoaded(state, actions.clipLoaded(clip)).draft).toEqual(
    draftFromClip(clip),
  );
});

test('save는 저장할 수 있을 때만 저장 중으로 바꾼다', () => {
  const state = loadedState(clip);
  expect(reduceLoaded(state, actions.save())).toEqual(state);
  const edited = reduceLoaded(state, actions.nameChanged('이름'));
  expect(reduceLoaded(edited, actions.save())).toEqual({
    ...edited,
    isSaving: true,
  });
  const saving = { ...edited, isSaving: true };
  expect(reduceLoaded(saving, actions.save())).toEqual(saving);
});

test('저장 중 추가 편집은 유지하고 저장된 값과 같은 초안은 정리한다', () => {
  const state = reduceLoaded(loadedState(clip), actions.nameChanged(' 이름 '));
  const saved = { ...clip, name: '이름' };
  const finished = reduceLoaded(
    { ...state, isSaving: true },
    actions.saved(saved),
  );
  expect(finished.isSaved).toBe(true);
  expect(finished.isSaving).toBe(false);
  expect(finished.draft.name).toBe('이름');
  const edited = { ...state, draft: { ...state.draft, name: '추가 편집' } };
  expect(reduceLoaded(edited, actions.saved(saved)).draft).toEqual(
    edited.draft,
  );
});

test('미리보기는 디코딩 완료까지 로딩을 유지하고 실제 방향의 비율을 쓴다', () => {
  const ready = reduceLoaded(
    loadedState(clip),
    actions.previewReady('file:///preview'),
  );
  expect(ready.preview.status).toBe('loading');
  const loaded = reduceLoaded(
    ready,
    actions.previewLoaded({ width: 3, height: 2 }),
  );
  expect(loaded.preview).toEqual({
    status: 'loaded',
    uri: 'file:///preview',
    aspectRatio: 1.5,
  });
  const failed = reduceLoaded(ready, actions.previewFailed());
  expect(failed.preview.status).toBe('failed');
  expect(failed.preview.uri).toBeNull();
  expect(
    reduceLoaded(failed, actions.previewLoaded({ width: 3, height: 2 }))
      .preview,
  ).toEqual(failed.preview);
});

test('크기가 0인 미리보기는 기존 비율을 유지한다', () => {
  const ready = reduceLoaded(
    loadedState(clip),
    actions.previewReady('file:///preview'),
  );
  const loaded = reduceLoaded(
    ready,
    actions.previewLoaded({ width: 0, height: 2 }),
  );
  expect(loaded.preview).toEqual({
    status: 'loaded',
    uri: 'file:///preview',
    aspectRatio: 4 / 3,
  });
});

test('삭제되면 진행 플래그와 시트를 닫고 늦은 미리보기를 무시한다', () => {
  const state = {
    ...loadedState(clip),
    isSaving: true,
    isDeleting: true,
    isSavingToPhotos: true,
    isDeleteSheetOpen: true,
  };
  const removed = reduceLoaded(state, actions.removed());
  expect(removed).toMatchObject({
    isRemoved: true,
    isSaving: false,
    isDeleting: false,
    isSavingToPhotos: false,
    isDeleteSheetOpen: false,
  });
  expect(
    reduceLoaded(removed, actions.previewReady('file:///preview')).preview,
  ).toEqual(removed.preview);
});

test.each<Action>([
  actions.nameChanged('이름'),
  actions.pinnedChanged(true),
  actions.save(),
  actions.saveFailed(),
  actions.deleteSheetShown(),
  actions.deleteSheetClosed(),
  actions.delete(),
  actions.deleteFailed(),
  actions.saveToPhotos(),
  actions.photoSaveFinished(),
  actions.previewReady('file:///preview'),
  actions.previewLoaded({ width: 3, height: 2 }),
  actions.previewFailed(),
  actions.removed(),
  actions.clipLoaded(clip),
  actions.saved(clip),
])('%j는 입력 상태를 변형하지 않는다', (action) => {
  const state = loadedState(clip);
  state.draft.name = '편집';
  const before = JSON.stringify(state);
  Object.freeze(state.draft);
  Object.freeze(state.preview);
  Object.freeze(state);
  reduce(state, action);
  expect(JSON.stringify(state)).toBe(before);
});

test('사진 저장과 삭제 플래그가 요청과 완료에 맞게 바뀐다', () => {
  const state = loadedState(clip);
  const saving = reduceLoaded(state, actions.saveToPhotos());
  expect(saving.isSavingToPhotos).toBe(true);
  expect(reduceLoaded(saving, actions.saveToPhotos())).toEqual(saving);
  expect(
    reduceLoaded(saving, actions.photoSaveFinished()).isSavingToPhotos,
  ).toBe(false);
  const sheet = reduceLoaded(state, actions.deleteSheetShown());
  expect(sheet.isDeleteSheetOpen).toBe(true);
  const deleting = reduceLoaded(sheet, actions.delete());
  expect(deleting.isDeleteSheetOpen).toBe(false);
  expect(deleting.isDeleting).toBe(true);
  expect(reduceLoaded(deleting, actions.delete())).toEqual(deleting);
  expect(reduceLoaded(deleting, actions.deleteFailed()).isDeleting).toBe(false);
});
