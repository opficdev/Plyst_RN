import { useEffect } from 'react';
import type { Dispatch } from 'react';
import { subscribeClipChanges, subscribeSearchVisibility } from 'plyst-bridge';
import type { HomeAction } from './homeState';
import { loadHomeClips } from './loadHomeClips';

export function useHomeClips(dispatch: Dispatch<HomeAction>) {
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
        const result = await loadHomeClips();
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
    const search = subscribeSearchVisibility((isVisible) => {
      if (!disposed) dispatch({ type: 'searchVisibilityChanged', isVisible });
    });
    subscribed = true;
    void reload();
    return () => {
      disposed = true;
      clips.remove();
      search.remove();
    };
  }, [dispatch]);
}
