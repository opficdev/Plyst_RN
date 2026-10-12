import { normalizedMemo, normalizedName } from '../../Model/clipDetailValues';
import { updateClipDetail } from '../../Service/Clip/updateDetail';
import type { ClipDetailUpdateResult } from '../../Service/Clip/updateDetail';
import type { Draft } from './draft';

export async function saveTextDetail(
  clipID: string,
  draft: Draft,
): Promise<ClipDetailUpdateResult> {
  return updateClipDetail(
    clipID,
    normalizedName(draft),
    normalizedMemo(draft),
    draft.isPinned,
  );
}
