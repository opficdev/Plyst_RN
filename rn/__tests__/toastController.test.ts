import { createToastController } from '../src/components/Toast/toastController';

beforeEach(() => jest.useFakeTimers());

afterEach(() => {
  jest.clearAllTimers();
  jest.useRealTimers();
});

test('전달한 메시지와 성공 여부로 토스트를 표시한다', () => {
  const controller = createToastController();

  controller.show('복사했습니다', true, 'copy');

  expect(controller.getSnapshot()).toEqual({
    toast: { id: 'copy', message: '복사했습니다', isSuccess: true },
    isVisible: true,
  });
});

test('2000ms 뒤에 숨기고 퇴장 완료 전까지 토스트를 유지한다', () => {
  const controller = createToastController();
  controller.show('복사하지 못했습니다', false, 'failure');
  const toast = controller.getSnapshot().toast;

  jest.advanceTimersByTime(1999);
  expect(controller.getSnapshot().isVisible).toBe(true);

  jest.advanceTimersByTime(1);
  expect(controller.getSnapshot()).toEqual({ toast, isVisible: false });
  expect(controller.getSnapshot().toast).toBe(toast);

  controller.dismissed('failure');
  expect(controller.getSnapshot()).toEqual({ toast: null, isVisible: false });
});

test('현재 토스트가 숨겨진 뒤에만 같은 식별자의 퇴장을 완료한다', () => {
  const controller = createToastController();
  controller.show('저장했습니다', true, 'save');
  const visible = controller.getSnapshot();

  controller.dismissed('save');
  expect(controller.getSnapshot()).toBe(visible);

  jest.advanceTimersByTime(2000);
  const hidden = controller.getSnapshot();
  controller.dismissed('other');
  expect(controller.getSnapshot()).toBe(hidden);

  controller.dismissed('save');
  expect(controller.getSnapshot()).toEqual({ toast: null, isVisible: false });
});

test('마지막 식별자가 같으면 표시 중이거나 숨겨진 뒤에도 무시한다', () => {
  const controller = createToastController();
  controller.show('복사했습니다', true, 'copy');
  const visible = controller.getSnapshot();

  jest.advanceTimersByTime(1000);
  controller.show('다른 메시지', false, 'copy');
  expect(controller.getSnapshot()).toBe(visible);

  jest.advanceTimersByTime(1000);
  const hidden = controller.getSnapshot();
  expect(hidden.isVisible).toBe(false);
  controller.show('다른 메시지', false, 'copy');
  expect(controller.getSnapshot()).toBe(hidden);

  controller.dismissed('copy');
  const dismissed = controller.getSnapshot();
  controller.show('다른 메시지', false, 'copy');
  expect(controller.getSnapshot()).toBe(dismissed);
});

test('새 토스트로 교체하면 이전 타이머와 퇴장 요청이 새 토스트를 숨기지 않는다', () => {
  const controller = createToastController();
  controller.show('첫 번째', true, 'first');
  jest.advanceTimersByTime(1000);

  controller.show('두 번째', false, 'second');
  const snapshot = controller.getSnapshot();
  expect(snapshot).toEqual({
    toast: { id: 'second', message: '두 번째', isSuccess: false },
    isVisible: true,
  });
  expect(jest.getTimerCount()).toBe(1);

  jest.advanceTimersByTime(1000);
  controller.dismissed('first');
  expect(controller.getSnapshot()).toBe(snapshot);

  jest.advanceTimersByTime(1000);
  const hidden = controller.getSnapshot();
  expect(hidden.isVisible).toBe(false);
  controller.dismissed('first');
  expect(controller.getSnapshot()).toBe(hidden);
});

test('식별자를 생략할 때마다 다른 숫자를 만들고 문자열 식별자와 구분한다', () => {
  const controller = createToastController();
  controller.show('첫 번째', true);
  const first = controller.getSnapshot().toast?.id;
  controller.show('두 번째', true);
  const second = controller.getSnapshot().toast?.id;

  expect(typeof first).toBe('number');
  expect(typeof second).toBe('number');
  expect(second).not.toBe(first);

  controller.show('문자열 식별자', false, String(second));
  expect(controller.getSnapshot().toast?.id).toBe(String(second));
});

test('마지막 식별자가 달라지면 이전 식별자를 다시 표시할 수 있다', () => {
  const controller = createToastController();
  controller.show('첫 번째', true, 'first');
  controller.show('두 번째', true, 'second');
  controller.show('첫 번째 다시', false, 'first');

  expect(controller.getSnapshot().toast).toEqual({
    id: 'first',
    message: '첫 번째 다시',
    isSuccess: false,
  });
});

test('상태가 바뀌면 구독자에게 알리고 구독 해제 뒤에는 알리지 않는다', () => {
  const controller = createToastController();
  const listener = jest.fn();
  const unsubscribe = controller.subscribe(listener);

  controller.show('복사했습니다', true, 'copy');
  expect(listener).toHaveBeenCalledTimes(1);
  controller.show('중복 요청', false, 'copy');
  controller.dismissed('copy');
  expect(listener).toHaveBeenCalledTimes(1);

  jest.advanceTimersByTime(2000);
  expect(listener).toHaveBeenCalledTimes(2);
  controller.dismissed('copy');
  expect(listener).toHaveBeenCalledTimes(3);

  unsubscribe();
  controller.show('저장했습니다', true, 'save');
  jest.advanceTimersByTime(2000);
  controller.dismissed('save');
  expect(listener).toHaveBeenCalledTimes(3);
});

test('상태가 바뀌지 않으면 스냅샷 참조를 유지한다', () => {
  const controller = createToastController();
  const initial = controller.getSnapshot();
  expect(controller.getSnapshot()).toBe(initial);
  controller.dismissed('missing');
  expect(controller.getSnapshot()).toBe(initial);

  controller.show('복사했습니다', true, 'copy');
  const visible = controller.getSnapshot();
  expect(visible).not.toBe(initial);
  expect(controller.getSnapshot()).toBe(visible);

  jest.advanceTimersByTime(2000);
  const hidden = controller.getSnapshot();
  expect(hidden).not.toBe(visible);
  expect(controller.getSnapshot()).toBe(hidden);

  controller.dismissed('copy');
  const dismissed = controller.getSnapshot();
  expect(dismissed).not.toBe(hidden);
  controller.dismissed('copy');
  expect(controller.getSnapshot()).toBe(dismissed);
});
