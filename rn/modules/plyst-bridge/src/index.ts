import NativePlystScreen from './NativePlystScreen';
import NativePlystClip from './NativePlystClip';
import type { ClipRecord } from './NativePlystClip';
import NativePlystToast from './NativePlystToast';
import type { ToastRequest } from './NativePlystToast';

export type { ClipImageRecord, ClipRecord } from './NativePlystClip';
export type { ToastRequest } from './NativePlystToast';

export function getClip(id: string): Promise<ClipRecord | null> {
  return NativePlystClip.getClip(id);
}

export function closeScreen(): void {
  NativePlystScreen.close();
}

export function subscribeToastRequests(
  listener: (request: ToastRequest) => void,
) {
  const subscription = NativePlystToast.onToastRequest(listener);
  NativePlystToast.ready();
  return subscription;
}
