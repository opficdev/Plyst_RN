import { normalizedMemo, normalizedName } from '../../Model/clipDetailValues';
import { updateClipDetail } from '../../Service/Clip/updateClipDetail';
import type { ClipDetailUpdateResult } from '../../Service/Clip/updateClipDetail';
import type { Draft } from './textDetailDraft';

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
