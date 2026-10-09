import { getClip } from 'plyst-bridge';
import type { ClipImageRecord, ClipRecord } from 'plyst-bridge';

export type ImageDetailResult =
  | { status: 'loaded'; clip: ClipRecord & { image: ClipImageRecord } }
  | { status: 'missing' }
  | { status: 'failed' };

export async function loadImageDetail(
  clipID: string,
): Promise<ImageDetailResult> {
  try {
    const clip = await getClip(clipID);
    if (clip === null) return { status: 'missing' };
    if (clip.image === null) return { status: 'failed' };
    return { status: 'loaded', clip: { ...clip, image: clip.image } };
  } catch {
    return { status: 'failed' };
  }
}
