import { createToastController } from '../src/components/Toast/controller';

beforeEach(() => jest.useFakeTimers());

afterEach(() => {
  jest.clearAllTimers();
  jest.useRealTimers();
});

test('전달한 메시지와 성공 여부로 토스트를 표시한다', () => {
  const controller = createToastController();

  controller.show('복사했습니다', true);
  const id = controller.getSnapshot().toast?.id;

  expect(controller.getSnapshot()).toEqual({
    toast: { id, message: '복사했습니다', isSuccess: true },
    isVisible: true,
  });
});

test('2000ms 뒤에 숨기고 퇴장 완료 전까지 토스트를 유지한다', () => {
  const controller = createToastController();
  controller.show('복사하지 못했습니다', false);
  const toast = controller.getSnapshot().toast;
  const id = controller.getSnapshot().toast?.id;

  jest.advanceTimersByTime(1999);
  expect(controller.getSnapshot().isVisible).toBe(true);

  jest.advanceTimersByTime(1);
  expect(controller.getSnapshot()).toEqual({ toast, isVisible: false });
  expect(controller.getSnapshot().toast).toBe(toast);

  controller.dismissed(id!);
  expect(controller.getSnapshot()).toEqual({ toast: null, isVisible: false });
});

test('현재 토스트가 숨겨진 뒤에만 같은 식별자의 퇴장을 완료한다', () => {
  const controller = createToastController();
  controller.show('저장했습니다', true);
  const id = controller.getSnapshot().toast?.id;
  const visible = controller.getSnapshot();

  controller.dismissed(id!);
  expect(controller.getSnapshot()).toBe(visible);

  jest.advanceTimersByTime(2000);
  const hidden = controller.getSnapshot();
  controller.dismissed(id! + 1);
  expect(controller.getSnapshot()).toBe(hidden);

  controller.dismissed(id!);
  expect(controller.getSnapshot()).toEqual({ toast: null, isVisible: false });
});

test('새 토스트로 교체하면 이전 타이머와 퇴장 요청이 새 토스트를 숨기지 않는다', () => {
  const controller = createToastController();
  controller.show('첫 번째', true);
  const first = controller.getSnapshot().toast?.id;
  jest.advanceTimersByTime(1000);

  controller.show('두 번째', false);
  const second = controller.getSnapshot().toast?.id;
  const snapshot = controller.getSnapshot();
  expect(snapshot).toEqual({
    toast: { id: second, message: '두 번째', isSuccess: false },
    isVisible: true,
  });
  expect(jest.getTimerCount()).toBe(1);

  jest.advanceTimersByTime(1000);
  controller.dismissed(first!);
  expect(controller.getSnapshot()).toBe(snapshot);

  jest.advanceTimersByTime(1000);
  const hidden = controller.getSnapshot();
  expect(hidden.isVisible).toBe(false);
  controller.dismissed(first!);
  expect(controller.getSnapshot()).toBe(hidden);
});

test('호출마다 다른 숫자 식별자를 만든다', () => {
  const controller = createToastController();
  controller.show('첫 번째', true);
  const first = controller.getSnapshot().toast?.id;
  controller.show('두 번째', true);
  const second = controller.getSnapshot().toast?.id;

  expect(typeof first).toBe('number');
  expect(typeof second).toBe('number');
  expect(second).not.toBe(first);
  expect(second).toBe(first! + 1);
});

test('상태가 바뀌면 구독자에게 알리고 구독 해제 뒤에는 알리지 않는다', () => {
  const controller = createToastController();
  const listener = jest.fn();
  const unsubscribe = controller.subscribe(listener);

  controller.show('복사했습니다', true);
  const id = controller.getSnapshot().toast?.id;
  expect(listener).toHaveBeenCalledTimes(1);
  controller.dismissed(id!);
  expect(listener).toHaveBeenCalledTimes(1);

  jest.advanceTimersByTime(2000);
  expect(listener).toHaveBeenCalledTimes(2);
  controller.dismissed(id!);
  expect(listener).toHaveBeenCalledTimes(3);

  unsubscribe();
  controller.show('저장했습니다', true);
  const saved = controller.getSnapshot().toast?.id;
  jest.advanceTimersByTime(2000);
  controller.dismissed(saved!);
  expect(listener).toHaveBeenCalledTimes(3);
});

test('상태가 바뀌지 않으면 스냅샷 참조를 유지한다', () => {
  const controller = createToastController();
  const initial = controller.getSnapshot();
  expect(controller.getSnapshot()).toBe(initial);
  controller.dismissed(-1);
  expect(controller.getSnapshot()).toBe(initial);

  controller.show('복사했습니다', true);
  const id = controller.getSnapshot().toast?.id;
  const visible = controller.getSnapshot();
  expect(visible).not.toBe(initial);
  expect(controller.getSnapshot()).toBe(visible);

  jest.advanceTimersByTime(2000);
  const hidden = controller.getSnapshot();
  expect(hidden).not.toBe(visible);
  expect(controller.getSnapshot()).toBe(hidden);

  controller.dismissed(id!);
  const dismissed = controller.getSnapshot();
  expect(dismissed).not.toBe(hidden);
  controller.dismissed(id!);
  expect(controller.getSnapshot()).toBe(dismissed);
});
