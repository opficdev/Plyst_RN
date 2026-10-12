import { saveClipImageToPhotos } from 'plyst-bridge';
import type { ClipPhotoSaveResult } from 'plyst-bridge';

export async function saveClipToPhotos(
  clipID: string,
): Promise<ClipPhotoSaveResult | 'removed' | 'failed'> {
  try {
    const result = await saveClipImageToPhotos(clipID);
    return result === null ? 'removed' : result;
  } catch {
    return 'failed';
  }
}
