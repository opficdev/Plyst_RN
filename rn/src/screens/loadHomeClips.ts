import { getClips } from 'plyst-bridge';
import type { ClipRecord } from 'plyst-bridge';

export type HomeClipsResult =
  { status: 'loaded'; clips: ClipRecord[] } | { status: 'failed' };

export async function loadHomeClips(): Promise<HomeClipsResult> {
  try {
    const clips = await getClips();
    return { status: 'loaded', clips };
  } catch {
    return { status: 'failed' };
  }
}
