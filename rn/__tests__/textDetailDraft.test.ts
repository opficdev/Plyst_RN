import type { ClipRecord } from 'plyst-bridge';
import {
  canSave,
  differs,
  draftFromClip,
  hasChanges,
  initialState,
  normalizedMemo,
  normalizedName,
  reduce,
} from '../src/screens/textDetailDraft';
import type {
  Draft,
  TextDetailAction,
  TextDetailState,
} from '../src/screens/textDetailDraft';

const clip: ClipRecord = {
  id: 'clip-id',
  text: '원문',
  characterCount: 2,
  image: null,
  name: null,
  memo: null,
  isPinned: false,
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
    draftFromClip({ ...clip, name: '이름', memo: '메모', isPinned: true }),
  ).toEqual({ name: '이름', memo: '메모', isPinned: true });
});

test.each<[string, string | null]>([
  ['  이름  ', '이름'],
  ['', null],
  [whitespace, null],
  [`${whitespace}이름${whitespace}`, '이름'],
  ['이 름\n본문', '이 름\n본문'],
  ['\uFEFF', '\uFEFF'],
  [`${whitespace}\uFEFF${whitespace}`, '\uFEFF'],
])('이름 %j을 정규화한다', (name, expected) => {
  expect(normalizedName({ ...draftFromClip(clip), name })).toBe(expected);
});

test.each<[string, string | null]>([
  ['', null],
  [whitespace, null],
  [`${whitespace}메모${whitespace}`, `${whitespace}메모${whitespace}`],
  ['\uFEFF', '\uFEFF'],
])('메모 %j의 공백 여부를 판정하고 내용을 보존한다', (memo, expected) => {
  expect(normalizedMemo({ ...draftFromClip(clip), memo })).toBe(expected);
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

test('초기 상태는 원본의 초안과 모두 꺼진 플래그를 가진다', () => {
  expect(initialState(clip)).toEqual({
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
  const state = initialState(clip);
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
    const state = initialState(clip);
    state.draft.name = '이름';
    expect(canSave({ ...state, [flag]: true })).toBe(false);
  },
);

const updated = { ...clip, name: '새 이름', memo: '새 메모', isPinned: true };

test('clipLoaded는 편집하지 않은 초안을 새 원본에 맞춘다', () => {
  const state = initialState(clip);
  expect(reduce(state, { type: 'clipLoaded', clip: updated })).toEqual({
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
  const state = initialState(clip);
  state.draft = { ...state.draft, ...change };
  expect(reduce(state, { type: 'clipLoaded', clip: updated })).toEqual({
    ...state,
    clip: updated,
  });
});

test('clipLoaded의 초안 비교는 정준 동등성을 적용하지 않는다', () => {
  const state = initialState({ ...clip, name: 'é' });
  state.draft.name = 'e\u0301';
  expect(hasChanges(state)).toBe(false);
  expect(reduce(state, { type: 'clipLoaded', clip: updated }).draft).toEqual(
    state.draft,
  );
});

test('saved는 저장된 값과 같은 초안을 정리한다', () => {
  const state = initialState(clip);
  state.isSaving = true;
  state.draft = { name: ' é ', memo: whitespace, isPinned: true };
  const saved = { ...clip, name: 'e\u0301', isPinned: true };
  expect(reduce(state, { type: 'saved', clip: saved })).toEqual({
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
  const state = initialState(clip);
  state.isSaving = true;
  state.draft = { ...draftFromClip(updated), ...change };
  expect(reduce(state, { type: 'saved', clip: updated })).toEqual({
    ...state,
    clip: updated,
    isSaving: false,
    isSaved: true,
  });
});

test.each<[TextDetailAction, Partial<TextDetailState>]>([
  [
    { type: 'nameChanged', name: '이름' },
    { draft: { name: '이름', memo: '', isPinned: false } },
  ],
  [
    { type: 'memoChanged', memo: '메모' },
    { draft: { name: '', memo: '메모', isPinned: false } },
  ],
  [
    { type: 'pinnedChanged', isPinned: true },
    { draft: { name: '', memo: '', isPinned: true } },
  ],
  [{ type: 'saveStarted' }, { isSaving: true }],
  [{ type: 'deleteSheetShown' }, { isDeleteSheetOpen: true }],
  [{ type: 'deleteStarted' }, { isDeleting: true, isDeleteSheetOpen: false }],
])('%j는 해당 상태만 변경한다', (action, change) => {
  const state = initialState(clip);
  expect(reduce(state, action)).toEqual({ ...state, ...change });
});

test.each<[TextDetailAction, Partial<TextDetailState>]>([
  [{ type: 'saveFailed' }, { isSaving: false }],
  [{ type: 'deleteFailed' }, { isDeleting: false }],
  [{ type: 'deleteSheetClosed' }, { isDeleteSheetOpen: false }],
  [{ type: 'deleteStarted' }, { isDeleting: true, isDeleteSheetOpen: false }],
  [
    { type: 'removed' },
    {
      isSaving: false,
      isDeleting: false,
      isRemoved: true,
      isDeleteSheetOpen: false,
    },
  ],
])('%j는 진행 중인 플래그와 시트를 규칙에 따라 해제한다', (action, change) => {
  const state = {
    ...initialState(clip),
    isSaving: true,
    isDeleting: true,
    isDeleteSheetOpen: true,
    isSaved: true,
  };
  expect(reduce(state, action)).toEqual({ ...state, ...change });
});

test.each<TextDetailAction>([
  { type: 'clipLoaded', clip: updated },
  { type: 'removed' },
  { type: 'nameChanged', name: '이름' },
  { type: 'memoChanged', memo: '메모' },
  { type: 'pinnedChanged', isPinned: true },
  { type: 'saveStarted' },
  { type: 'saved', clip: updated },
  { type: 'saveFailed' },
  { type: 'deleteSheetShown' },
  { type: 'deleteSheetClosed' },
  { type: 'deleteStarted' },
  { type: 'deleteFailed' },
])('%j는 입력을 변형하지 않고 새 상태와 초안을 반환한다', (action) => {
  const state = initialState(Object.freeze({ ...clip }));
  const before = {
    ...state,
    clip: { ...state.clip },
    draft: { ...state.draft },
  };
  Object.freeze(state.draft);
  Object.freeze(state);
  if ('clip' in action) Object.freeze(action.clip);
  const next = reduce(state, Object.freeze(action));
  expect(state).toEqual(before);
  expect(next).not.toBe(state);
  expect(next.draft).not.toBe(state.draft);
});
