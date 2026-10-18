import {
  subscribeClipboardSaveRequests,
  copyClip,
  saveCurrentClipboard,
  deleteClip,
  getClip,
  getClips,
  getClipImagePreview,
  getClipThumbnail,
  saveClipImageToPhotos,
  subscribeClipChanges,
  updateClip,
} from 'plyst-bridge';
import type { ClipRecord } from 'plyst-bridge';

import NativePlystHome from '../modules/plyst-bridge/src/NativePlystHome';
import NativePlystClip from '../modules/plyst-bridge/src/NativePlystClip';

jest.mock('../modules/plyst-bridge/src/NativePlystClip', () => ({
  __esModule: true,
  default: {
    onClipChange: jest.fn(),
    ready: jest.fn(),
    getClip: jest.fn(),
    getClips: jest.fn(),
    getClipImagePreview: jest.fn(),
    getClipThumbnail: jest.fn(),
    saveClipImageToPhotos: jest.fn(),
    updateClip: jest.fn(),
    deleteClip: jest.fn(),
    copyClip: jest.fn(),
    saveCurrentClipboard: jest.fn(),
  },
}));

jest.mock('../modules/plyst-bridge/src/NativePlystHome', () => ({
  __esModule: true,
  default: {
    ready: jest.fn(),
    onClipboardSaveRequest: jest.fn(),
  },
}));

jest.mock(
  '../modules/plyst-bridge/src/PlystDetailBarButtonNativeComponent',
  () => ({ __esModule: true, default: 'PlystDetailBarButton' }),
);
const native = jest.mocked(NativePlystClip);

beforeEach(() => jest.resetAllMocks());

test('식별자를 전달하고 클립의 필드를 그대로 반환한다', async () => {
  const record: ClipRecord = {
    id: 'clip-id',
    text: null,
    isWebLink: false,
    image: {
      byteCount: 100,
      contentType: 'public.png',
      pixelWidth: 2,
      pixelHeight: 3,
    },
    name: null,
    memo: '메모',
    pinnedAt: 1000,
    createdAt: 1234500,
    lastUsedAt: null,
  };
  native.getClip.mockResolvedValue(record);

  await expect(getClip(record.id)).resolves.toBe(record);
  expect(native.getClip).toHaveBeenCalledWith(record.id);
  expect(native.getClip).toHaveBeenCalledTimes(1);
});

test('전체 클립 목록의 순서와 필드를 그대로 반환한다', async () => {
  const records: ClipRecord[] = [
    {
      id: 'link-id',
      text: 'https://example.com',
      image: null,
      name: null,
      memo: null,
      pinnedAt: null,
      isWebLink: true,
      createdAt: 2000,
      lastUsedAt: null,
    },
    {
      id: 'text-id',
      text: '원문',
      image: null,
      name: null,
      memo: null,
      pinnedAt: null,
      isWebLink: false,
      createdAt: 1000,
      lastUsedAt: null,
    },
  ];
  native.getClips.mockResolvedValue(records);

  await expect(getClips()).resolves.toBe(records);
  expect(native.getClips).toHaveBeenCalledWith();
  expect(native.getClips).toHaveBeenCalledTimes(1);
});

test('클립이 없으면 빈 목록을 반환한다', async () => {
  native.getClips.mockResolvedValue([]);

  await expect(getClips()).resolves.toEqual([]);
});

test.each(['E_UNAVAILABLE', 'E_READ_FAILED', 'E_CORRUPTED_DATA'])(
  '목록 조회의 %s 오류를 그대로 전달한다',
  async (code) => {
    const error = Object.assign(new Error(code), { code });
    native.getClips.mockRejectedValue(error);

    await expect(getClips()).rejects.toBe(error);
  },
);

test('없는 클립은 null을 반환한다', async () => {
  native.getClip.mockResolvedValue(null);

  await expect(getClip('missing')).resolves.toBeNull();
});

test.each([
  'E_INVALID_ID',
  'E_UNAVAILABLE',
  'E_READ_FAILED',
  'E_CORRUPTED_DATA',
])('%s 오류를 그대로 전달한다', async (code) => {
  const error = Object.assign(new Error(code), { code });
  native.getClip.mockRejectedValue(error);

  await expect(getClip('id')).rejects.toBe(error);
});

test('갱신 인자를 그대로 전달하고 저장된 클립을 반환한다', async () => {
  const record: ClipRecord = {
    id: 'clip-id',
    text: '원문',
    isWebLink: false,
    image: null,
    name: ' 이름 ',
    memo: null,
    pinnedAt: 1000,
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
    callback({ kind: 'inserted', id: 'clip-id' });
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
    [{ kind: 'inserted', id: 'clip-id' }],
    [{ kind: 'updated', id: 'clip-id' }],
    [{ kind: 'deleted', id: 'clip-id' }],
  ]);
});

test.each(['file:///images/preview', null])(
  '미리보기 %s를 전달한다',
  async (uri) => {
    native.getClipImagePreview.mockResolvedValue(uri);
    await expect(getClipImagePreview('clip-id')).resolves.toBe(uri);
    expect(native.getClipImagePreview).toHaveBeenCalledWith('clip-id');
  },
);

test.each(['saved', 'denied', 'restricted', null])(
  '사진 저장 %s를 전달한다',
  async (result) => {
    native.saveClipImageToPhotos.mockResolvedValue(result);
    await expect(saveClipImageToPhotos('clip-id')).resolves.toBe(result);
    expect(native.saveClipImageToPhotos).toHaveBeenCalledWith('clip-id');
  },
);

test.each(['E_INVALID_ID', 'E_UNAVAILABLE', 'E_IMAGE_UNAVAILABLE'])(
  '미리보기 %s 오류를 전달한다',
  async (code) => {
    const error = Object.assign(new Error(code), { code });
    native.getClipImagePreview.mockRejectedValue(error);
    await expect(getClipImagePreview('id')).rejects.toBe(error);
  },
);

test.each(['E_INVALID_ID', 'E_UNAVAILABLE', 'E_PHOTO_SAVE_FAILED'])(
  '사진 저장 %s 오류를 전달한다',
  async (code) => {
    const error = Object.assign(new Error(code), { code });
    native.saveClipImageToPhotos.mockRejectedValue(error);
    await expect(saveClipImageToPhotos('id')).rejects.toBe(error);
  },
);

test.each(['file:///images/thumbnail-240', null])(
  '썸네일 %s와 요청한 크기를 전달한다',
  async (uri) => {
    native.getClipThumbnail.mockResolvedValue(uri);
    await expect(getClipThumbnail('clip-id', 240)).resolves.toBe(uri);
    expect(native.getClipThumbnail).toHaveBeenCalledWith('clip-id', 240);
  },
);

test.each(['E_INVALID_ID', 'E_UNAVAILABLE', 'E_IMAGE_UNAVAILABLE'])(
  '썸네일 %s 오류를 전달한다',
  async (code) => {
    const error = Object.assign(new Error(code), { code });
    native.getClipThumbnail.mockRejectedValue(error);
    await expect(getClipThumbnail('id', 240)).rejects.toBe(error);
  },
);
test.each(['saved', 'empty', 'unsupported', 'accessFailed', 'invalidImage'])(
  '현재 클립보드 저장 결과 %s를 그대로 전달한다',
  async (result) => {
    native.saveCurrentClipboard.mockResolvedValue(result);
    await expect(saveCurrentClipboard()).resolves.toBe(result);
    expect(native.saveCurrentClipboard).toHaveBeenCalledWith();
    expect(native.saveCurrentClipboard).toHaveBeenCalledTimes(1);
  },
);

test.each(['E_UNAVAILABLE', 'E_SAVE_FAILED'])(
  '현재 클립보드 저장 오류 %s를 그대로 전달한다',
  async (code) => {
    const error = Object.assign(new Error(code), { code });
    native.saveCurrentClipboard.mockRejectedValue(error);
    await expect(saveCurrentClipboard()).rejects.toBe(error);
  },
);

test.each(['👨‍👩‍👧‍👦🇰🇷e\u0301'.repeat(20), null])(
  '네이티브 원본 필드를 가공하지 않고 전달한다',
  async (text) => {
    const record: ClipRecord = {
      id: 'clip-id',
      text,
      image:
        text === null
          ? {
              byteCount: 1000,
              contentType: 'public.png',
              pixelWidth: 1,
              pixelHeight: 1,
            }
          : null,
      name: null,
      memo: null,
      pinnedAt: null,
      isWebLink: false,
      createdAt: 1000,
      lastUsedAt: null,
    };
    native.getClip.mockResolvedValue(record);
    await expect(getClip(record.id)).resolves.toBe(record);
  },
);

test('클립보드 저장 요청 리스너를 등록한 뒤 준비를 알리고 구독 객체를 반환한다', () => {
  const home = jest.mocked(NativePlystHome);
  const listener = jest.fn();
  const subscription = { remove: jest.fn() } as unknown as ReturnType<
    typeof home.onClipboardSaveRequest
  >;
  home.onClipboardSaveRequest.mockImplementation(() => {
    expect(home.ready).not.toHaveBeenCalled();
    return subscription;
  });
  home.ready.mockImplementation(() => {
    expect(home.onClipboardSaveRequest).toHaveReturnedWith(subscription);
    home.onClipboardSaveRequest.mock.calls[0][0]();
  });

  expect(subscribeClipboardSaveRequests(listener)).toBe(subscription);
  expect(home.onClipboardSaveRequest).toHaveBeenCalledWith(listener);
  expect(home.onClipboardSaveRequest).toHaveBeenCalledTimes(1);
  expect(home.ready).toHaveBeenCalledTimes(1);
  expect(listener).toHaveBeenCalledWith();
  expect(listener).toHaveBeenCalledTimes(1);
});
