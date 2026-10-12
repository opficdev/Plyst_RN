import { useCallback, useEffect, useLayoutEffect, useRef } from 'react';
import type { Dispatch } from 'react';
import type { ViewToken } from '@shopify/flash-list';
import type { ClipRecord } from 'plyst-bridge';
import type { ClipThumbnailAction, ClipThumbnails } from './clipThumbnails';
import { loadClipThumbnail } from '../../Service/Clip/loadClipThumbnail';
import { createThumbnailRequestQueue } from './clipThumbnailRequests';

const viewabilityConfig = {
  viewAreaCoveragePercentThreshold: 0,
  minimumViewTime: 0,
};

type ThumbnailState = Pick<
  ClipThumbnails,
  'thumbnails' | 'loadingThumbnails' | 'failedThumbnails'
> & { clips: ClipRecord[] };
type ThumbnailItem = { kind: 'card'; clip: ClipRecord } | { kind: string };

export function useClipThumbnails<Item extends ThumbnailItem>(
  state: ThumbnailState,
  dispatch: Dispatch<ClipThumbnailAction>,
  gridPixels: number,
  pinnedPixels: number,
  isMeasured: boolean,
) {
  const current = useRef({ state, gridPixels, pinnedPixels, isMeasured });
  const queue = useRef<ReturnType<typeof createThumbnailRequestQueue> | null>(
    null,
  );
  const visibleIds = useRef<string[]>([]);
  const pinnedIds = useRef<string[]>([]);
  const visibleKeys = useRef(new Map<string, { id: string; pixels: number }>());
  const timers = useRef(new Set<ReturnType<typeof setTimeout>>());

  useLayoutEffect(() => {
    current.current = { state, gridPixels, pinnedPixels, isMeasured };
  }, [state, gridPixels, pinnedPixels, isMeasured]);

  useEffect(() => {
    const requests = createThumbnailRequestQueue({
      load: loadClipThumbnail,
      onStarted: (key) => dispatch({ type: 'thumbnailStarted', key }),
      onLoaded: (key, uri) => dispatch({ type: 'thumbnailLoaded', key, uri }),
      onFailed: (key) => dispatch({ type: 'thumbnailFailed', key }),
      onCancelled: (key) => dispatch({ type: 'thumbnailCancelled', key }),
    });
    queue.current = requests;
    const pending = timers.current;
    return () => {
      requests.dispose();
      queue.current = null;
      for (const timer of pending) clearTimeout(timer);
      pending.clear();
    };
  }, [dispatch]);

  const request = useCallback((id: string, pixels: number) => {
    const { state } = current.current;
    const key = `${id}:${pixels}`;
    if (
      state.thumbnails[key] ||
      state.loadingThumbnails[key] ||
      state.failedThumbnails[key]
    )
      return;
    if (state.clips.some((clip) => clip.id === id && clip.image !== null))
      queue.current?.request(id, pixels);
  }, []);

  const updateGrid = useCallback(() => {
    const { gridPixels, isMeasured, state } = current.current;
    const next = new Map<string, { id: string; pixels: number }>();
    if (isMeasured) {
      for (const id of visibleIds.current) {
        if (!state.clips.some((clip) => clip.id === id && clip.image !== null))
          continue;
        next.set(`${id}:${gridPixels}`, { id, pixels: gridPixels });
        request(id, gridPixels);
      }
    }
    for (const [key, value] of visibleKeys.current) {
      if (next.has(key)) continue;
      const timer = setTimeout(() => {
        timers.current.delete(timer);
        if (!visibleKeys.current.has(key))
          queue.current?.cancel(value.id, value.pixels);
      }, 0);
      timers.current.add(timer);
    }
    visibleKeys.current = next;
  }, [request]);

  useEffect(() => {
    updateGrid();
    for (const id of pinnedIds.current) request(id, pinnedPixels);
  }, [state.clips, gridPixels, pinnedPixels, isMeasured, request, updateGrid]);

  const onViewableItemsChanged = useCallback(
    ({ viewableItems }: { viewableItems: ViewToken<Item>[] }) => {
      visibleIds.current = viewableItems.flatMap(({ item }) =>
        item.kind === 'card' && 'clip' in item && item.clip.image !== null
          ? [item.clip.id]
          : [],
      );
      updateGrid();
    },
    [updateGrid],
  );

  const onViewableIdsChange = useCallback(
    (ids: string[]) => {
      pinnedIds.current = ids;
      for (const id of ids) request(id, current.current.pinnedPixels);
    },
    [request],
  );

  return { viewabilityConfig, onViewableItemsChanged, onViewableIdsChange };
}
