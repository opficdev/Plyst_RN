import { subscribeClipChanges } from 'plyst-bridge';
import type { ScreenScope } from '../../Shared/State/screenStore';
import { loadClips } from '../../Service/Clip/loadClips';

export function startClipReload<State>(
  scope: ScreenScope<State>,
  onReload?: () => void,
) {
  let subscribed = false;
  let loading = false;
  let pending = false;
  async function reload() {
    if (scope.isDisposed()) return;
    if (!subscribed || loading) {
      pending = true;
      return;
    }
    loading = true;
    do {
      pending = false;
      onReload?.();
      const result = await loadClips();
      if (scope.isDisposed()) return;
      scope.dispatch(
        result.status === 'loaded'
          ? { type: 'clipsLoaded', clips: result.clips, now: Date.now() }
          : { type: 'loadFailed' },
      );
    } while (pending);
    loading = false;
  }
  const clips = subscribeClipChanges(() => {
    void reload();
  });
  subscribed = true;
  void reload();
  scope.onDispose(() => clips.remove());
}
