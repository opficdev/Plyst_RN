import NativePlystScreen from './NativePlystScreen';
import NativePlystClip from './NativePlystClip';
import type { ClipRecord } from './NativePlystClip';
import NativePlystToast from './NativePlystToast';
import type { ToastRequest } from './NativePlystToast';

export type { ClipImageRecord, ClipRecord } from './NativePlystClip';
export type { ToastRequest } from './NativePlystToast';

export type ClipChange = {
  kind: 'updated' | 'deleted';
  id: string;
};

export function subscribeClipChanges(listener: (change: ClipChange) => void) {
  const subscription = NativePlystClip.onClipChange((change) => {
    listener(change as ClipChange);
  });
  NativePlystClip.ready();
  return subscription;
}

export type ClipCopyResult =
  'copied' | 'copiedWithoutLastUsedAt' | 'writeNotObserved';

export function copyClip(id: string): Promise<ClipCopyResult | null> {
  return NativePlystClip.copyClip(id) as Promise<ClipCopyResult | null>;
}

export function getClip(id: string): Promise<ClipRecord | null> {
  return NativePlystClip.getClip(id);
}

export function updateClip(
  id: string,
  name: string | null,
  memo: string | null,
  isPinned: boolean,
): Promise<ClipRecord | null> {
  return NativePlystClip.updateClip(id, name, memo, isPinned);
}

export function deleteClip(id: string): Promise<void> {
  return NativePlystClip.deleteClip(id);
}

export function closeScreen(): void {
  NativePlystScreen.close();
}

export function setSaveEnabled(isEnabled: boolean): void {
  NativePlystScreen.setSaveEnabled(isEnabled);
}

export function subscribeSave(listener: () => void) {
  const subscription = NativePlystScreen.onSave(listener);
  NativePlystScreen.ready();
  return subscription;
}

export function subscribeToastRequests(
  listener: (request: ToastRequest) => void,
) {
  const subscription = NativePlystToast.onToastRequest(listener);
  NativePlystToast.ready();
  return subscription;
}
