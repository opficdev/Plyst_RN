import { subscribeClipChanges } from 'plyst-bridge';
import { loadClips } from '../../Service/Clip/load';
import type { ClipGridActions } from './reducers';

type ReloadActions = Pick<ClipGridActions, 'clipsLoaded' | 'loadFailed'>;

// 변경 구독을 시작하고 구독을 끊는 정리 함수를 돌려줍니다.
export function startClipReload(
  api: {
    signal: AbortSignal;
    dispatch: (
      action:
        | ReturnType<ReloadActions['clipsLoaded']>
        | ReturnType<ReloadActions['loadFailed']>,
    ) => unknown;
  },
  actions: ReloadActions,
  onReload?: () => void,
) {
  let subscribed = false;
  let loading = false;
  let pending = false;
  async function reload() {
    if (api.signal.aborted) return;
    if (!subscribed || loading) {
      pending = true;
      return;
    }
    loading = true;
    do {
      pending = false;
      onReload?.();
      const result = await loadClips();
      if (api.signal.aborted) return;
      api.dispatch(
        result.status === 'loaded'
          ? actions.clipsLoaded({ clips: result.clips, now: Date.now() })
          : actions.loadFailed(),
      );
    } while (pending);
    loading = false;
  }
  const clips = subscribeClipChanges(() => {
    void reload();
  });
  subscribed = true;
  void reload();
  return () => clips.remove();
}
