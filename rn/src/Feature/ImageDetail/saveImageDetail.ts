import { normalizedName } from '../../Model/clipDetailValues';
import { updateClipDetail } from '../../Service/Clip/updateClipDetail';
import type { ClipDetailUpdateResult } from '../../Service/Clip/updateClipDetail';
import type { Draft } from './imageDetailDraft';

export async function saveImageDetail(
  clipID: string,
  draft: Draft,
  memo: string | null,
): Promise<ClipDetailUpdateResult> {
  return updateClipDetail(clipID, normalizedName(draft), memo, draft.isPinned);
}
