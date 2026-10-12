import { normalizedName } from '../../Model/clipDetailValues';
import { updateClipDetail } from '../../Service/Clip/updateDetail';
import type { ClipDetailUpdateResult } from '../../Service/Clip/updateDetail';
import type { Draft } from './draft';

export async function saveImageDetail(
  clipID: string,
  draft: Draft,
  memo: string | null,
): Promise<ClipDetailUpdateResult> {
  return updateClipDetail(clipID, normalizedName(draft), memo, draft.isPinned);
}
