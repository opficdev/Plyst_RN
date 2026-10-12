import { getClipThumbnail } from 'plyst-bridge';

export type ClipThumbnailResult =
  | { status: 'loaded'; uri: string }
  | { status: 'missing' }
  | { status: 'failed' };

export async function loadClipThumbnail(
  clipID: string,
  pixels: number,
): Promise<ClipThumbnailResult> {
  try {
    const uri = await getClipThumbnail(clipID, pixels);
    return uri === null ? { status: 'missing' } : { status: 'loaded', uri };
  } catch {
    return { status: 'failed' };
  }
}
