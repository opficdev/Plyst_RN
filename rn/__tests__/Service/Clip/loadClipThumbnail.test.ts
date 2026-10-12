import { getClipThumbnail } from 'plyst-bridge';
import { loadClipThumbnail } from '../../../src/Service/Clip/loadClipThumbnail';

jest.mock('plyst-bridge', () => ({ getClipThumbnail: jest.fn() }));
const getClipThumbnailMock = jest.mocked(getClipThumbnail);

beforeEach(() => jest.resetAllMocks());

test('불러온 썸네일 주소를 포함한 loaded이다', async () => {
  getClipThumbnailMock.mockResolvedValue('file:///thumbnail.png');
  await expect(loadClipThumbnail('clip-id', 200)).resolves.toEqual({
    status: 'loaded',
    uri: 'file:///thumbnail.png',
  });
  expect(getClipThumbnailMock).toHaveBeenCalledWith('clip-id', 200);
  expect(getClipThumbnailMock).toHaveBeenCalledTimes(1);
});

test('브리지 결과가 null이면 missing이다', async () => {
  getClipThumbnailMock.mockResolvedValue(null);
  await expect(loadClipThumbnail('clip-id', 200)).resolves.toEqual({
    status: 'missing',
  });
});

test('브리지 오류가 발생하면 failed이다', async () => {
  getClipThumbnailMock.mockRejectedValue(
    Object.assign(new Error('요청 실패'), { code: 'E_IMAGE_UNAVAILABLE' }),
  );
  await expect(loadClipThumbnail('clip-id', 200)).resolves.toEqual({
    status: 'failed',
  });
});

test('유효하지 않은 크기로 브리지 오류가 발생하면 failed이다', async () => {
  getClipThumbnailMock.mockRejectedValue(
    Object.assign(new Error('유효하지 않은 크기'), {
      code: 'E_IMAGE_UNAVAILABLE',
    }),
  );
  await expect(loadClipThumbnail('clip-id', 0)).resolves.toEqual({
    status: 'failed',
  });
  expect(getClipThumbnailMock).toHaveBeenCalledWith('clip-id', 0);
  expect(getClipThumbnailMock).toHaveBeenCalledTimes(1);
});
