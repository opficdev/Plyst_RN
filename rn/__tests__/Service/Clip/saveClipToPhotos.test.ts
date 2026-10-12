import { saveClipImageToPhotos } from 'plyst-bridge';
import { saveClipToPhotos } from '../../../src/Service/Clip/saveClipToPhotos';

jest.mock('plyst-bridge', () => ({ saveClipImageToPhotos: jest.fn() }));
const saveClipImageToPhotosMock = jest.mocked(saveClipImageToPhotos);

beforeEach(() => jest.resetAllMocks());

test.each(['saved', 'denied', 'restricted'] as const)(
  '사진 저장 결과가 %s이면 반환값도 같은 값이다',
  async (result) => {
    saveClipImageToPhotosMock.mockResolvedValue(result);
    await expect(saveClipToPhotos('clip-id')).resolves.toBe(result);
    expect(saveClipImageToPhotosMock).toHaveBeenCalledWith('clip-id');
    expect(saveClipImageToPhotosMock).toHaveBeenCalledTimes(1);
  },
);

test('사진 저장 결과가 null이면 removed이다', async () => {
  saveClipImageToPhotosMock.mockResolvedValue(null);
  await expect(saveClipToPhotos('clip-id')).resolves.toBe('removed');
});

test('브리지 오류가 발생하면 failed이다', async () => {
  saveClipImageToPhotosMock.mockRejectedValue(
    Object.assign(new Error('사진 저장 실패'), { code: 'E_PHOTO_SAVE_FAILED' }),
  );
  await expect(saveClipToPhotos('clip-id')).resolves.toBe('failed');
});
