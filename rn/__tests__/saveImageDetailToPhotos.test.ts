import { saveClipImageToPhotos } from 'plyst-bridge';
import { saveImageDetailToPhotos } from '../src/screens/saveImageDetailToPhotos';

jest.mock('plyst-bridge', () => ({ saveClipImageToPhotos: jest.fn() }));
const save = jest.mocked(saveClipImageToPhotos);
beforeEach(() => jest.resetAllMocks());

test.each([
  ['saved', '사진 앱에 저장했습니다', true],
  ['denied', '사진 추가 권한이 없습니다. 설정에서 허용해 주세요', false],
  ['restricted', '이 기기에서는 사진 추가가 제한되어 있습니다', false],
] as const)(
  '%s 결과의 토스트를 반환한다',
  async (result, message, isSuccess) => {
    save.mockResolvedValue(result);
    await expect(saveImageDetailToPhotos('id')).resolves.toEqual({
      status: 'finished',
      message,
      isSuccess,
    });
    expect(save).toHaveBeenCalledWith('id');
    expect(save).toHaveBeenCalledTimes(1);
  },
);

test('없는 클립은 토스트 없이 닫는다', async () => {
  save.mockResolvedValue(null);
  await expect(saveImageDetailToPhotos('id')).resolves.toEqual({
    status: 'removed',
  });
});

test('쓰기 실패는 실패 토스트를 반환한다', async () => {
  save.mockRejectedValue(new Error('E_PHOTO_SAVE_FAILED'));
  await expect(saveImageDetailToPhotos('id')).resolves.toEqual({
    status: 'finished',
    message: '사진 앱에 저장하지 못했습니다',
    isSuccess: false,
  });
});
