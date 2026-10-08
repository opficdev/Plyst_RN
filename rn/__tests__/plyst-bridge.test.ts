import {
  closeScreen,
  copyClip,
  deleteClip,
  getClip,
  setSaveEnabled,
  subscribeClipChanges,
  subscribeSave,
  subscribeToastRequests,
  updateClip,
} from 'plyst-bridge';
import type { ClipRecord } from 'plyst-bridge';

import NativePlystScreen from '../modules/plyst-bridge/src/NativePlystScreen';
import NativePlystClip from '../modules/plyst-bridge/src/NativePlystClip';
import NativePlystToast from '../modules/plyst-bridge/src/NativePlystToast';

jest.mock('../modules/plyst-bridge/src/NativePlystToast', () => ({
  __esModule: true,
  default: { onToastRequest: jest.fn(), ready: jest.fn() },
}));

jest.mock('../modules/plyst-bridge/src/NativePlystClip', () => ({
  __esModule: true,
  default: {
    onClipChange: jest.fn(),
    ready: jest.fn(),
    getClip: jest.fn(),
    updateClip: jest.fn(),
    deleteClip: jest.fn(),
    copyClip: jest.fn(),
  },
}));

jest.mock('../modules/plyst-bridge/src/NativePlystScreen', () => ({
  __esModule: true,
  default: {
    close: jest.fn(),
    setSaveEnabled: jest.fn(),
    onSave: jest.fn(),
    ready: jest.fn(),
  },
}));

const native = jest.mocked(NativePlystClip);

beforeEach(() => jest.resetAllMocks());

test('식별자를 전달하고 클립의 필드를 그대로 반환한다', async () => {
  const record: ClipRecord = {
    id: 'clip-id',
    text: null,
    characterCount: 0,
    image: {
      uri: 'file:///images/original',
      contentType: 'public.png',
      pixelWidth: 2,
      pixelHeight: 3,
    },
    name: null,
    memo: '메모',
    isPinned: true,
    createdAt: 1234500,
    lastUsedAt: null,
  };
  native.getClip.mockResolvedValue(record);

  await expect(getClip(record.id)).resolves.toBe(record);
  expect(native.getClip).toHaveBeenCalledWith(record.id);
  expect(native.getClip).toHaveBeenCalledTimes(1);
});

test('없는 클립은 null을 반환한다', async () => {
  native.getClip.mockResolvedValue(null);

  await expect(getClip('missing')).resolves.toBeNull();
});

test.each([
  'E_INVALID_ID',
  'E_UNAVAILABLE',
  'E_READ_FAILED',
  'E_CORRUPTED_DATA',
  'E_IMAGE_UNAVAILABLE',
])('%s 오류를 그대로 전달한다', async (code) => {
  const error = Object.assign(new Error(code), { code });
  native.getClip.mockRejectedValue(error);

  await expect(getClip('id')).rejects.toBe(error);
});

test('화면 닫기를 네이티브 모듈에 전달한다', () => {
  closeScreen();
  expect(NativePlystScreen.close).toHaveBeenCalledTimes(1);
  expect(NativePlystScreen.close).toHaveBeenCalledWith();
});

test('토스트 요청을 구독한 뒤 준비를 알리고 구독 객체를 반환한다', () => {
  const toast = jest.mocked(NativePlystToast);
  const listener = jest.fn();
  const subscription = { remove: jest.fn() } as unknown as ReturnType<
    typeof NativePlystToast.onToastRequest
  >;
  toast.onToastRequest.mockImplementation(() => {
    expect(toast.ready).not.toHaveBeenCalled();
    return subscription;
  });
  toast.ready.mockImplementation(() => {
    expect(toast.onToastRequest).toHaveReturnedWith(subscription);
  });

  expect(subscribeToastRequests(listener)).toBe(subscription);
  expect(toast.onToastRequest).toHaveBeenCalledWith(listener);
  expect(toast.onToastRequest).toHaveBeenCalledTimes(1);
  expect(toast.ready).toHaveBeenCalledTimes(1);
});

test('갱신 인자를 그대로 전달하고 저장된 클립을 반환한다', async () => {
  const record: ClipRecord = {
    id: 'clip-id',
    text: '원문',
    characterCount: 2,
    image: null,
    name: ' 이름 ',
    memo: null,
    isPinned: true,
    createdAt: 1000,
    lastUsedAt: null,
  };
  native.updateClip.mockResolvedValue(record);

  await expect(updateClip(record.id, ' 이름 ', null, true)).resolves.toBe(
    record,
  );
  expect(native.updateClip).toHaveBeenCalledWith(
    record.id,
    ' 이름 ',
    null,
    true,
  );
  expect(native.updateClip).toHaveBeenCalledTimes(1);
});

test('없는 클립의 갱신은 null을 반환한다', async () => {
  native.updateClip.mockResolvedValue(null);

  await expect(
    updateClip('missing', null, ' 메모 ', false),
  ).resolves.toBeNull();
  expect(native.updateClip).toHaveBeenCalledWith(
    'missing',
    null,
    ' 메모 ',
    false,
  );
});

test('삭제 식별자를 그대로 전달하고 반환값 없이 완료한다', async () => {
  native.deleteClip.mockResolvedValue(undefined);

  await expect(deleteClip('clip-id')).resolves.toBeUndefined();
  expect(native.deleteClip).toHaveBeenCalledWith('clip-id');
  expect(native.deleteClip).toHaveBeenCalledTimes(1);
});

test.each([
  'E_INVALID_ID',
  'E_UNAVAILABLE',
  'E_WRITE_FAILED',
  'E_CORRUPTED_DATA',
])('갱신과 삭제의 %s 오류를 그대로 전달한다', async (code) => {
  const error = Object.assign(new Error(code), { code });
  native.updateClip.mockRejectedValue(error);
  native.deleteClip.mockRejectedValue(error);

  await expect(updateClip('id', null, null, false)).rejects.toBe(error);
  await expect(deleteClip('id')).rejects.toBe(error);
});

test.each(['copied', 'copiedWithoutLastUsedAt', 'writeNotObserved'])(
  '복사 식별자를 전달하고 %s 결과를 그대로 반환한다',
  async (result) => {
    native.copyClip.mockResolvedValue(result);

    await expect(copyClip('clip-id')).resolves.toBe(result);
    expect(native.copyClip).toHaveBeenCalledWith('clip-id');
    expect(native.copyClip).toHaveBeenCalledTimes(1);
  },
);

test('없는 클립의 복사는 null을 반환한다', async () => {
  native.copyClip.mockResolvedValue(null);

  await expect(copyClip('missing')).resolves.toBeNull();
  expect(native.copyClip).toHaveBeenCalledWith('missing');
});

test('클립 변경을 구독한 뒤 준비를 알리고 구독 객체를 반환한다', () => {
  const listener = jest.fn();
  const subscription = { remove: jest.fn() } as unknown as ReturnType<
    typeof NativePlystClip.onClipChange
  >;
  native.onClipChange.mockImplementation((callback) => {
    expect(native.ready).not.toHaveBeenCalled();
    callback({ kind: 'updated', id: 'clip-id' });
    callback({ kind: 'deleted', id: 'clip-id' });
    return subscription;
  });
  native.ready.mockImplementation(() => {
    expect(native.onClipChange).toHaveReturnedWith(subscription);
  });

  expect(subscribeClipChanges(listener)).toBe(subscription);
  expect(native.onClipChange).toHaveBeenCalledTimes(1);
  expect(native.ready).toHaveBeenCalledTimes(1);
  expect(listener.mock.calls).toEqual([
    [{ kind: 'updated', id: 'clip-id' }],
    [{ kind: 'deleted', id: 'clip-id' }],
  ]);
});

test.each([true, false])('저장 버튼 활성 여부 %s를 전달한다', (isEnabled) => {
  setSaveEnabled(isEnabled);

  expect(NativePlystScreen.setSaveEnabled).toHaveBeenCalledWith(isEnabled);
  expect(NativePlystScreen.setSaveEnabled).toHaveBeenCalledTimes(1);
});

test('저장 탭을 구독한 뒤 준비를 알리고 구독 객체를 반환한다', () => {
  const screen = jest.mocked(NativePlystScreen);
  const listener = jest.fn();
  const subscription = { remove: jest.fn() } as unknown as ReturnType<
    typeof NativePlystScreen.onSave
  >;
  screen.onSave.mockImplementation((callback) => {
    expect(screen.ready).not.toHaveBeenCalled();
    callback();
    return subscription;
  });
  screen.ready.mockImplementation(() => {
    expect(screen.onSave).toHaveReturnedWith(subscription);
  });

  expect(subscribeSave(listener)).toBe(subscription);
  expect(screen.onSave).toHaveBeenCalledWith(listener);
  expect(screen.onSave).toHaveBeenCalledTimes(1);
  expect(screen.ready).toHaveBeenCalledTimes(1);
  expect(listener).toHaveBeenCalledWith();
  expect(listener).toHaveBeenCalledTimes(1);
});
