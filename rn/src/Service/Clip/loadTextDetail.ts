import { getClip } from 'plyst-bridge';
import type { ClipRecord } from 'plyst-bridge';

export type TextDetailResult =
  | { status: 'loaded'; clip: ClipRecord & { text: string } }
  | { status: 'missing' }
  | { status: 'failed' };

export async function loadTextDetail(
  clipID: string,
): Promise<TextDetailResult> {
  try {
    const clip = await getClip(clipID);
    if (clip === null) return { status: 'missing' };
    if (clip.text === null) return { status: 'failed' };
    return { status: 'loaded', clip: { ...clip, text: clip.text } };
  } catch {
    return { status: 'failed' };
  }
}
