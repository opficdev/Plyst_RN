import type { ClipRecord } from 'plyst-bridge';
import {
  canSave,
  differs,
  draftFromClip,
  initialState,
  reduce,
} from '../src/screens/imageDetailDraft';
import type { ImageDetailAction } from '../src/screens/imageDetailDraft';

const clip: ClipRecord = {
  id: 'id',
  text: null,
  characterCount: 0,
  isWebLink: false,
  image: {
    contentType: 'public.png',
    pixelWidth: 2,
    pixelHeight: 3,
    byteCountText: '100 bytes',
  },
  name: null,
  memo: '보존할 메모',
  isPinned: false,
  createdAt: 1000,
  lastUsedAt: null,
};

test('초기 초안은 이름과 고정만 가지고 미리보기는 로딩 중이다', () => {
  const state = initialState(clip);
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
    const state = reduce(initialState(clip), {
      type: 'nameChanged',
      name: '편집',
    });
    expect(canSave(state)).toBe(true);
    expect(canSave({ ...state, [flag]: true })).toBe(false);
    expect(canSave({ ...state, isSavingToPhotos: true })).toBe(true);
  },
);

test('외부 변경은 편집하지 않은 초안만 갱신하고 미리보기는 유지한다', () => {
  const state = reduce(initialState(clip), {
    type: 'previewReady',
    uri: 'file:///preview',
  });
  const updated = { ...clip, name: '외부 이름', isPinned: true };
  const loaded = reduce(state, { type: 'clipLoaded', clip: updated });
  expect(loaded.draft).toEqual(draftFromClip(updated));
  expect(loaded.preview).toEqual(state.preview);
  const edited = reduce(state, { type: 'nameChanged', name: '내 이름' });
  const refreshed = reduce(edited, { type: 'clipLoaded', clip: updated });
  expect(refreshed.draft).toEqual(edited.draft);
  expect(refreshed.clip).toBe(updated);
});

test('초안 비교는 Swift 문자열처럼 정준 동등성을 적용한다', () => {
  const state = initialState({ ...clip, name: 'é' });
  state.draft.name = 'e\u0301';
  expect(reduce(state, { type: 'clipLoaded', clip }).draft).toEqual(
    draftFromClip(clip),
  );
});

test('저장 중 추가 편집은 유지하고 저장된 값과 같은 초안은 정리한다', () => {
  const state = reduce(initialState(clip), {
    type: 'nameChanged',
    name: ' 이름 ',
  });
  const saved = { ...clip, name: '이름' };
  const finished = reduce(
    { ...state, isSaving: true },
    { type: 'saved', clip: saved },
  );
  expect(finished.isSaved).toBe(true);
  expect(finished.isSaving).toBe(false);
  expect(finished.draft.name).toBe('이름');
  const edited = { ...state, draft: { ...state.draft, name: '추가 편집' } };
  expect(reduce(edited, { type: 'saved', clip: saved }).draft).toEqual(
    edited.draft,
  );
});

test('미리보기는 디코딩 완료까지 로딩을 유지하고 실제 방향의 비율을 쓴다', () => {
  const ready = reduce(initialState(clip), {
    type: 'previewReady',
    uri: 'file:///preview',
  });
  expect(ready.preview.status).toBe('loading');
  const loaded = reduce(ready, { type: 'previewLoaded', width: 3, height: 2 });
  expect(loaded.preview).toEqual({
    status: 'loaded',
    uri: 'file:///preview',
    aspectRatio: 1.5,
  });
  const failed = reduce(ready, { type: 'previewFailed' });
  expect(failed.preview.status).toBe('failed');
  expect(failed.preview.uri).toBeNull();
  expect(
    reduce(failed, { type: 'previewLoaded', width: 3, height: 2 }).preview,
  ).toEqual(failed.preview);
});

test('삭제되면 진행 플래그와 시트를 닫고 늦은 미리보기를 무시한다', () => {
  const state = {
    ...initialState(clip),
    isSaving: true,
    isDeleting: true,
    isSavingToPhotos: true,
    isDeleteSheetOpen: true,
  };
  const removed = reduce(state, { type: 'removed' });
  expect(removed).toMatchObject({
    isRemoved: true,
    isSaving: false,
    isDeleting: false,
    isSavingToPhotos: false,
    isDeleteSheetOpen: false,
  });
  expect(
    reduce(removed, { type: 'previewReady', uri: 'file:///preview' }).preview,
  ).toEqual(removed.preview);
});

test.each<ImageDetailAction>([
  { type: 'nameChanged', name: '이름' },
  { type: 'pinnedChanged', isPinned: true },
  { type: 'saveStarted' },
  { type: 'saveFailed' },
  { type: 'deleteSheetShown' },
  { type: 'deleteSheetClosed' },
  { type: 'deleteStarted' },
  { type: 'deleteFailed' },
  { type: 'photoSaveStarted' },
  { type: 'photoSaveFinished' },
  { type: 'previewReady', uri: 'file:///preview' },
  { type: 'previewLoaded', width: 3, height: 2 },
  { type: 'previewFailed' },
  { type: 'removed' },
  { type: 'clipLoaded', clip },
  { type: 'saved', clip },
])('%j는 입력 상태를 변형하지 않는다', (action) => {
  const state = initialState(clip);
  const before = JSON.stringify(state);
  Object.freeze(state.draft);
  Object.freeze(state.preview);
  Object.freeze(state);
  const next = reduce(state, action);
  expect(JSON.stringify(state)).toBe(before);
  expect(next).not.toBe(state);
  expect(next.draft).not.toBe(state.draft);
});

test('사진 저장과 삭제 플래그가 요청과 완료에 맞게 바뀐다', () => {
  const state = initialState(clip);
  const saving = reduce(state, { type: 'photoSaveStarted' });
  expect(saving.isSavingToPhotos).toBe(true);
  expect(reduce(saving, { type: 'photoSaveFinished' }).isSavingToPhotos).toBe(
    false,
  );
  const sheet = reduce(state, { type: 'deleteSheetShown' });
  expect(sheet.isDeleteSheetOpen).toBe(true);
  const deleting = reduce(sheet, { type: 'deleteStarted' });
  expect(deleting.isDeleteSheetOpen).toBe(false);
  expect(deleting.isDeleting).toBe(true);
  expect(reduce(deleting, { type: 'deleteFailed' }).isDeleting).toBe(false);
});
