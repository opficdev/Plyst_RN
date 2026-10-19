import type { ClipRecord } from '../../../src/Model/clipRecord';
import {
  canSave,
  canStartDelete,
  canStartSave,
  differs,
  draftFromClip,
  hasChanges,
  isClosed,
  isSaveEnabled,
  loadedState,
  textDetailActions as actions,
  textDetailSlice,
} from '../../../src/Feature/TextDetail/draft';
import type {
  Draft,
  TextDetailLoaded,
  TextDetailStoreState,
} from '../../../src/Feature/TextDetail/draft';

const clip: ClipRecord = {
  id: 'clip-id',
  text: '원문',
  characterCount: 2,
  textPrefix: '원문',
  isWebLink: false,
  image: null,
  name: null,
  memo: null,
  pinnedAt: null,
  createdAt: 1234500,
  lastUsedAt: null,
};
const whitespace =
  '\t\n\v\f\r\u0020\u0085\u00A0\u1680\u2000\u2001\u2002\u2003\u2004\u2005\u2006\u2007\u2008\u2009\u200A\u2028\u2029\u202F\u205F\u3000';

test('원본의 null을 빈 문자열로 바꾸고 고정 여부를 유지한다', () => {
  expect(draftFromClip(clip)).toEqual({
    name: '',
    memo: '',
    isPinned: false,
  });
  expect(
    draftFromClip({ ...clip, name: '이름', memo: '메모', pinnedAt: 1000 }),
  ).toEqual({ name: '이름', memo: '메모', isPinned: true });
});

test.each<[Partial<Draft>, boolean]>([
  [{}, false],
  [{ name: '이름' }, true],
  [{ memo: '메모' }, true],
  [{ isPinned: true }, true],
  [{ name: whitespace, memo: whitespace }, false],
])('초안 변경 %j을 판정한다', (change, expected) => {
  expect(differs({ ...draftFromClip(clip), ...change }, clip)).toBe(expected);
});

test('이름의 앞뒤 공백은 변경으로 보지 않고 메모의 공백은 구분한다', () => {
  const original = { ...clip, name: '이름', memo: '메모' };
  const draft = draftFromClip(original);
  expect(differs({ ...draft, name: '  이름\n' }, original)).toBe(false);
  expect(differs({ ...draft, memo: ' 메모 ' }, original)).toBe(true);
});

test.each([
  ['한글', '\u1112\u1161\u11AB\u1100\u1173\u11AF'],
  ['é', 'e\u0301'],
  ['e\u0301', 'é'],
])('이름과 메모의 정준 동등성을 비교한다: %s', (original, equivalent) => {
  const record = { ...clip, name: original, memo: original };
  expect(
    differs({ name: equivalent, memo: equivalent, isPinned: false }, record),
  ).toBe(false);
});

test.each(['name', 'memo'] as const)(
  '원본 %s의 빈 문자열과 null을 구분한다',
  (field) => {
    const original = { ...clip, [field]: '' };
    expect(differs(draftFromClip(original), original)).toBe(true);
  },
);

type Action = Parameters<typeof textDetailSlice.reducer>[1];

function reduce(state: TextDetailStoreState, action: Action) {
  return textDetailSlice.reducer(state, action);
}
function reduceLoaded(state: TextDetailLoaded, action: Action) {
  return reduce(state, action) as TextDetailLoaded;
}

const loading = { phase: 'loading' } as const;
const closed = { phase: 'closed' } as const;

test('초기 상태는 조회 전이다', () => {
  expect(textDetailSlice.getInitialState()).toEqual(loading);
});

test('조회된 상태는 원본의 초안과 모두 꺼진 플래그를 가진다', () => {
  expect(loadedState(clip)).toEqual({
    phase: 'loaded',
    clip,
    draft: draftFromClip(clip),
    isSaving: false,
    isDeleting: false,
    isRemoved: false,
    isSaved: false,
    isDeleteSheetOpen: false,
  });
});

test('변경이 있을 때만 저장할 수 있다', () => {
  const state = loadedState(clip);
  expect(hasChanges(state)).toBe(false);
  expect(canSave(state)).toBe(false);
  const changed = { ...state, draft: { ...state.draft, name: '이름' } };
  expect(hasChanges(changed)).toBe(true);
  expect(canSave(changed)).toBe(true);
  expect(canSave({ ...changed, isSaved: true, isDeleteSheetOpen: true })).toBe(
    true,
  );
});

test.each(['isSaving', 'isDeleting', 'isRemoved'] as const)(
  '%s이면 변경이 있어도 저장할 수 없다',
  (flag) => {
    const state = loadedState(clip);
    state.draft.name = '이름';
    expect(canSave({ ...state, [flag]: true })).toBe(false);
  },
);

test('저장 버튼은 저장 뒤에도 켜져 있지만 저장 시작은 막는다', () => {
  const state = {
    ...loadedState(clip),
    draft: { name: '이름', memo: '', isPinned: false },
  };
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

test('닫힘은 조회 실패나 삭제 또는 저장 완료로 판정한다', () => {
  const state = loadedState(clip);
  expect(isClosed(loading)).toBe(false);
  expect(isClosed(closed)).toBe(true);
  expect(isClosed(state)).toBe(false);
  expect(isClosed({ ...state, isRemoved: true })).toBe(true);
  expect(isClosed({ ...state, isSaved: true })).toBe(true);
});

const updated = { ...clip, name: '새 이름', memo: '새 메모', pinnedAt: 1000 };

test('조회 전에는 편집과 저장과 삭제 시작이 상태를 바꾸지 않는다', () => {
  for (const action of [
    actions.nameChanged('이름'),
    actions.memoChanged('메모'),
    actions.pinnedChanged(true),
    actions.save(),
    actions.delete(),
    actions.saved(updated),
    actions.saveFailed(),
    actions.deleteSheetShown(),
    actions.deleteSheetClosed(),
    actions.deleteFailed(),
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

test('clipLoaded는 편집하지 않은 초안을 새 원본에 맞춘다', () => {
  const state = loadedState(clip);
  expect(reduceLoaded(state, actions.clipLoaded(updated))).toEqual({
    ...state,
    clip: updated,
    draft: draftFromClip(updated),
  });
});

test.each<Partial<Draft>>([
  { name: '편집한 이름' },
  { memo: '편집한 메모' },
  { isPinned: true },
  { name: ' ' },
])('clipLoaded는 편집 중인 초안 %j을 유지한다', (change) => {
  const state = loadedState(clip);
  state.draft = { ...state.draft, ...change };
  expect(reduceLoaded(state, actions.clipLoaded(updated))).toEqual({
    ...state,
    clip: updated,
  });
});

test.each(['isRemoved', 'isSaved'] as const)(
  'clipLoaded는 %s인 상태를 바꾸지 않는다',
  (flag) => {
    const state = { ...loadedState(clip), [flag]: true };
    expect(reduceLoaded(state, actions.clipLoaded(updated))).toEqual(state);
  },
);

test('clipLoaded의 초안 비교는 정준 동등성을 적용하지 않는다', () => {
  const state = loadedState({ ...clip, name: 'é' });
  state.draft.name = 'e\u0301';
  expect(hasChanges(state)).toBe(false);
  expect(reduceLoaded(state, actions.clipLoaded(updated)).draft).toEqual(
    state.draft,
  );
});

test('saved는 저장된 값과 같은 초안을 정리한다', () => {
  const state = loadedState(clip);
  state.isSaving = true;
  state.draft = { name: ' é ', memo: whitespace, isPinned: true };
  const saved = { ...clip, name: 'e\u0301', pinnedAt: 1000 };
  expect(reduceLoaded(state, actions.saved(saved))).toEqual({
    ...state,
    clip: saved,
    draft: draftFromClip(saved),
    isSaving: false,
    isSaved: true,
  });
});

test.each<Partial<Draft>>([
  { name: '추가 이름' },
  { memo: '추가 메모' },
  { isPinned: false },
])('saved는 저장 중 추가 편집 %j을 보존한다', (change) => {
  const state = loadedState(clip);
  state.isSaving = true;
  state.draft = { ...draftFromClip(updated), ...change };
  expect(reduceLoaded(state, actions.saved(updated))).toEqual({
    ...state,
    clip: updated,
    isSaving: false,
    isSaved: true,
  });
});

test.each<[Action, Partial<TextDetailLoaded>]>([
  [
    actions.nameChanged('이름'),
    { draft: { name: '이름', memo: '', isPinned: false } },
  ],
  [
    actions.memoChanged('메모'),
    { draft: { name: '', memo: '메모', isPinned: false } },
  ],
  [
    actions.pinnedChanged(true),
    { draft: { name: '', memo: '', isPinned: true } },
  ],
  [actions.deleteSheetShown(), { isDeleteSheetOpen: true }],
])('%j는 해당 상태만 변경한다', (action, change) => {
  const state = loadedState(clip);
  expect(reduceLoaded(state, action)).toEqual({ ...state, ...change });
});

test('save는 저장할 수 있을 때만 저장 중으로 바꾼다', () => {
  const state = loadedState(clip);
  expect(reduceLoaded(state, actions.save())).toEqual(state);
  const edited = { ...state, draft: { ...state.draft, name: '이름' } };
  expect(reduceLoaded(edited, actions.save())).toEqual({
    ...edited,
    isSaving: true,
  });
  const saving = { ...edited, isSaving: true };
  expect(reduceLoaded(saving, actions.save())).toEqual(saving);
});

test('delete는 삭제를 시작하면서 시트를 닫고 진행 중에는 다시 시작하지 않는다', () => {
  const state = { ...loadedState(clip), isDeleteSheetOpen: true };
  const started = reduceLoaded(state, actions.delete());
  expect(started).toEqual({
    ...state,
    isDeleting: true,
    isDeleteSheetOpen: false,
  });
  expect(canStartDelete(started)).toBe(false);
  expect(reduceLoaded(started, actions.delete())).toEqual(started);
});

test.each<[Action, Partial<TextDetailLoaded>]>([
  [actions.saveFailed(), { isSaving: false }],
  [actions.deleteFailed(), { isDeleting: false }],
  [actions.deleteSheetClosed(), { isDeleteSheetOpen: false }],
  [
    actions.removed(),
    {
      isSaving: false,
      isDeleting: false,
      isRemoved: true,
      isDeleteSheetOpen: false,
    },
  ],
])('%j는 진행 중인 플래그와 시트를 규칙에 따라 해제한다', (action, change) => {
  const state = {
    ...loadedState(clip),
    isSaving: true,
    isDeleting: true,
    isDeleteSheetOpen: true,
    isSaved: true,
  };
  expect(reduceLoaded(state, action)).toEqual({ ...state, ...change });
});

test.each<Action>([
  actions.clipLoaded(updated),
  actions.removed(),
  actions.nameChanged('이름'),
  actions.memoChanged('메모'),
  actions.pinnedChanged(true),
  actions.save(),
  actions.saved(updated),
  actions.saveFailed(),
  actions.deleteSheetShown(),
  actions.deleteSheetClosed(),
  actions.delete(),
  actions.deleteFailed(),
])('%j는 입력 상태를 변형하지 않는다', (action) => {
  const state = loadedState(Object.freeze({ ...clip }));
  state.draft.name = '편집';
  const before = {
    ...state,
    clip: { ...state.clip },
    draft: { ...state.draft },
  };
  Object.freeze(state.draft);
  Object.freeze(state);
  reduce(state, action);
  expect(state).toEqual(before);
});
