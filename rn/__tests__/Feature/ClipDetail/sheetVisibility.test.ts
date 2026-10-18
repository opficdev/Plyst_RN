import {
  initialSheetVisibility,
  isSheetVisible,
  reduceSheetVisibility,
} from '../../../src/Feature/ClipDetail/sheetVisibility';

test('처음에는 시트를 보여 준다', () => {
  expect(isSheetVisible(initialSheetVisibility, false)).toBe(true);
});

test('present가 끝나기 전의 닫기 요청은 onShow까지 보관한다', () => {
  const requested = reduceSheetVisibility(
    initialSheetVisibility,
    'closeRequested',
  );
  expect(isSheetVisible(requested, false)).toBe(true);
  const shown = reduceSheetVisibility(requested, 'shown');
  expect(isSheetVisible(shown, false)).toBe(false);
});

test('present가 끝난 뒤에는 화면이 닫혀야 할 때 시트를 숨긴다', () => {
  const shown = reduceSheetVisibility(initialSheetVisibility, 'shown');
  expect(isSheetVisible(shown, false)).toBe(true);
  expect(isSheetVisible(shown, true)).toBe(false);
});

test('present가 끝나기 전에 화면이 닫혀야 해도 onShow까지 보관한다', () => {
  expect(isSheetVisible(initialSheetVisibility, true)).toBe(true);
});

test('스와이프로 닫은 뒤에는 화면이 닫혀야 해도 visible을 바꾸지 않는다', () => {
  const swiped = reduceSheetVisibility(
    reduceSheetVisibility(initialSheetVisibility, 'shown'),
    'swiped',
  );
  expect(isSheetVisible(swiped, true)).toBe(true);
  expect(isSheetVisible(swiped, false)).toBe(true);
});

test.each(['shown', 'closeRequested', 'swiped'] as const)(
  '%s를 반복해도 같은 상태를 반환한다',
  (action) => {
    const once = reduceSheetVisibility(initialSheetVisibility, action);
    expect(reduceSheetVisibility(once, action)).toBe(once);
  },
);
