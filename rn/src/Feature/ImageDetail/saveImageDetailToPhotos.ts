import { saveClipImageToPhotos } from 'plyst-bridge';

export type SaveImageDetailToPhotosResult =
  | { status: 'removed' }
  | { status: 'finished'; message: string; isSuccess: boolean };

export async function saveImageDetailToPhotos(
  clipID: string,
): Promise<SaveImageDetailToPhotosResult> {
  try {
    const result = await saveClipImageToPhotos(clipID);
    if (result === null) return { status: 'removed' };
    const messages = {
      saved: '사진 앱에 저장했습니다',
      denied: '사진 추가 권한이 없습니다. 설정에서 허용해 주세요',
      restricted: '이 기기에서는 사진 추가가 제한되어 있습니다',
    };
    return {
      status: 'finished',
      message: messages[result],
      isSuccess: result === 'saved',
    };
  } catch {
    return {
      status: 'finished',
      message: '사진 앱에 저장하지 못했습니다',
      isSuccess: false,
    };
  }
}
