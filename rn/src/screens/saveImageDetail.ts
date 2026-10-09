import { updateClip } from 'plyst-bridge';
import type { ClipRecord } from 'plyst-bridge';
import { normalizedName } from './clipDetailValues';
import type { Draft } from './imageDetailDraft';

export type SaveImageDetailResult =
  | { status: 'saved'; clip: ClipRecord }
  | { status: 'removed' }
  | { status: 'failed' };

export async function saveImageDetail(
  clipID: string,
  draft: Draft,
  memo: string | null,
): Promise<SaveImageDetailResult> {
  try {
    const clip = await updateClip(
      clipID,
      normalizedName(draft),
      memo,
      draft.isPinned,
    );
    if (clip === null) return { status: 'removed' };
    return { status: 'saved', clip };
  } catch {
    return { status: 'failed' };
  }
}
