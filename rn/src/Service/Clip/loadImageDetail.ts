import { getClip } from 'plyst-bridge';
import { makeClipRecord } from '../../Model/clipRecord';
import type { ClipImageRecord, ClipRecord } from '../../Model/clipRecord';

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
    return {
      status: 'loaded',
      clip: { ...makeClipRecord(clip), image: clip.image },
    };
  } catch {
    return { status: 'failed' };
  }
}
