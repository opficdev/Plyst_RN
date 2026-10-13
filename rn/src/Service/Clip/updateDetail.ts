import { updateClip } from 'plyst-bridge';
import { makeClipRecord } from '../../Model/clipRecord';
import type { ClipRecord } from '../../Model/clipRecord';

export type ClipDetailUpdateResult =
  | { status: 'saved'; clip: ClipRecord }
  | { status: 'removed' }
  | { status: 'failed' };

export async function updateClipDetail(
  clipID: string,
  name: string | null,
  memo: string | null,
  isPinned: boolean,
): Promise<ClipDetailUpdateResult> {
  try {
    const clip = await updateClip(clipID, name, memo, isPinned);
    if (clip === null) return { status: 'removed' };
    return { status: 'saved', clip: makeClipRecord(clip) };
  } catch {
    return { status: 'failed' };
  }
}
