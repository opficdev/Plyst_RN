import { updateClip } from 'plyst-bridge';
import type { ClipRecord } from 'plyst-bridge';
import { normalizedMemo, normalizedName } from './textDetailDraft';
import type { Draft } from './textDetailDraft';

export type SaveTextDetailResult =
  | { status: 'saved'; clip: ClipRecord }
  | { status: 'removed' }
  | { status: 'failed' };

export async function saveTextDetail(
  clipID: string,
  draft: Draft,
): Promise<SaveTextDetailResult> {
  try {
    const clip = await updateClip(
      clipID,
      normalizedName(draft),
      normalizedMemo(draft),
      draft.isPinned,
    );
    if (clip === null) return { status: 'removed' };
    return { status: 'saved', clip };
  } catch {
    return { status: 'failed' };
  }
}
