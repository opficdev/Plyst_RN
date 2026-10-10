import { getClip } from 'plyst-bridge';
import type { ClipRecord } from 'plyst-bridge';
import { loadImageDetail } from '../src/screens/loadImageDetail';

jest.mock('plyst-bridge', () => ({ getClip: jest.fn() }));
const getClipMock = jest.mocked(getClip);
const clip: ClipRecord = {
  id: 'clip-id',
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
  memo: null,
  isPinned: false,
  createdAt: 1234500,
  lastUsedAt: null,
};

beforeEach(() => jest.resetAllMocks());

test('이미지 클립을 반환한다', async () => {
  getClipMock.mockResolvedValue(clip);
  await expect(loadImageDetail(clip.id)).resolves.toEqual({
    status: 'loaded',
    clip,
  });
  expect(getClipMock).toHaveBeenCalledWith(clip.id);
  expect(getClipMock).toHaveBeenCalledTimes(1);
});

test('조회 결과가 null이면 missing이다', async () => {
  getClipMock.mockResolvedValue(null);
  await expect(loadImageDetail(clip.id)).resolves.toEqual({
    status: 'missing',
  });
});

test('브리지 오류가 발생하면 failed이다', async () => {
  getClipMock.mockRejectedValue(
    Object.assign(new Error('읽기 실패'), { code: 'E_READ_FAILED' }),
  );
  await expect(loadImageDetail(clip.id)).resolves.toEqual({ status: 'failed' });
});

test('이미지가 null이면 failed이다', async () => {
  getClipMock.mockResolvedValue({ ...clip, image: null });
  await expect(loadImageDetail(clip.id)).resolves.toEqual({ status: 'failed' });
});
