import { getClips } from 'plyst-bridge';
import { makeClipRecord } from '../../Model/clipRecord';
import type { ClipRecord } from '../../Model/clipRecord';

export type ClipsResult =
  { status: 'loaded'; clips: ClipRecord[] } | { status: 'failed' };

export async function loadClips(): Promise<ClipsResult> {
  try {
    const clips = await getClips();
    return { status: 'loaded', clips: clips.map(makeClipRecord) };
  } catch {
    return { status: 'failed' };
  }
}
