import NativePlystScreen from './NativePlystScreen';
import NativePlystClip from './NativePlystClip';
import type { ClipRecord } from './NativePlystClip';

export type { ClipImageRecord, ClipRecord } from './NativePlystClip';

export function getClip(id: string): Promise<ClipRecord | null> {
  return NativePlystClip.getClip(id);
}

export function closeScreen(): void {
  NativePlystScreen.close();
}
