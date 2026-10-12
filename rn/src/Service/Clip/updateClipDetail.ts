import { updateClip } from 'plyst-bridge';
import type { ClipRecord } from 'plyst-bridge';

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
    return { status: 'saved', clip };
  } catch {
    return { status: 'failed' };
  }
}
