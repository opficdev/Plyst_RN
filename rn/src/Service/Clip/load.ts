import { getClips } from 'plyst-bridge';
import type { ClipRecord } from 'plyst-bridge';

export type ClipsResult =
  { status: 'loaded'; clips: ClipRecord[] } | { status: 'failed' };

export async function loadClips(): Promise<ClipsResult> {
  try {
    const clips = await getClips();
    return { status: 'loaded', clips };
  } catch {
    return { status: 'failed' };
  }
}
