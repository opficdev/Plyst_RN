import { useEffect } from 'react';
import type { Dispatch } from 'react';
import { subscribeClipChanges } from 'plyst-bridge';
import type { ClipRecord } from 'plyst-bridge';
import { loadClips } from './loadClips';

type ClipLoadAction =
  | { type: 'clipsLoaded'; clips: ClipRecord[]; now: number }
  | { type: 'loadFailed' };

export function useClips(
  dispatch: Dispatch<ClipLoadAction>,
  onReload?: () => void,
) {
  useEffect(() => {
    let disposed = false;
    let subscribed = false;
    let loading = false;
    let pending = false;
    async function reload() {
      if (disposed) return;
      if (!subscribed || loading) {
        pending = true;
        return;
      }
      loading = true;
      do {
        pending = false;
        onReload?.();
        const result = await loadClips();
        if (disposed) return;
        dispatch(
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
    return () => {
      disposed = true;
      clips.remove();
    };
  }, [dispatch, onReload]);
}
