import { getClip } from 'plyst-bridge';
import type { ClipRecord } from 'plyst-bridge';

import NativePlystClip from '../modules/plyst-bridge/src/NativePlystClip';

jest.mock('../modules/plyst-bridge/src/NativePlystClip', () => ({
  __esModule: true,
  default: { getClip: jest.fn() },
}));

const native = jest.mocked(NativePlystClip);

beforeEach(() => jest.resetAllMocks());

test('식별자를 전달하고 클립의 필드를 그대로 반환한다', async () => {
  const record: ClipRecord = {
    id: 'clip-id',
    text: null,
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
