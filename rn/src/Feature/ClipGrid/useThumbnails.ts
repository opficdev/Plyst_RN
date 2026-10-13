import { useCallback, useEffect, useLayoutEffect, useRef } from 'react';
import type { Dispatch } from 'react';
import type { ViewToken } from '@shopify/flash-list';
import type { ClipRecord } from '../../Model/clipRecord';
import type { ClipThumbnails } from './thumbnails';
import { clipThumbnailActions as actions } from './thumbnailListener';

const viewabilityConfig = {
  viewAreaCoveragePercentThreshold: 0,
  minimumViewTime: 0,
};

type ThumbnailState = ClipThumbnails & { clips: ClipRecord[] };
type ThumbnailItem = { kind: 'card'; clip: ClipRecord } | { kind: string };

export function useClipThumbnails<Item extends ThumbnailItem>(
  state: ThumbnailState,
  dispatch: Dispatch<ReturnType<(typeof actions)[keyof typeof actions]>>,
  gridPixels: number,
  pinnedPixels: number,
  isMeasured: boolean,
) {
  const current = useRef({ state, gridPixels, pinnedPixels, isMeasured });
  const visibleIds = useRef<string[]>([]);
  const pinnedIds = useRef<string[]>([]);
  const isPinnedVisible = useRef(false);
  const previousOrder = useRef(state.thumbnailOrder);
  const visibleKeys = useRef(new Map<string, { id: string; pixels: number }>());
  const timers = useRef(new Set<ReturnType<typeof setTimeout>>());

  useLayoutEffect(() => {
    current.current = { state, gridPixels, pinnedPixels, isMeasured };
  }, [state, gridPixels, pinnedPixels, isMeasured]);

  useEffect(() => {
    const pending = timers.current;
    return () => {
      for (const timer of pending) clearTimeout(timer);
      pending.clear();
    };
  }, [dispatch]);

  const request = useCallback(
    (id: string, pixels: number) => {
      const { state } = current.current;
      const key = `${id}:${pixels}`;
      if (
        state.thumbnails[key] ||
        state.loadingThumbnails[key] ||
        state.failedThumbnails[key]
      )
        return;
      if (state.clips.some((clip) => clip.id === id && clip.image !== null))
        dispatch(actions.thumbnailRequested({ id, pixels }));
    },
    [dispatch],
  );

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
          dispatch(actions.thumbnailCancelled(value));
      }, 0);
      timers.current.add(timer);
    }
    visibleKeys.current = next;
  }, [dispatch, request]);

  useEffect(() => {
    updateGrid();
    for (const id of pinnedIds.current) request(id, pinnedPixels);
  }, [state.clips, gridPixels, pinnedPixels, isMeasured, request, updateGrid]);

  useEffect(() => {
    const order = previousOrder.current;
    previousOrder.current = state.thumbnailOrder;
    if (!isPinnedVisible.current) return;
    for (const id of pinnedIds.current) {
      const pixels = current.current.pinnedPixels;
      const key = `${id}:${pixels}`;
      if (order.includes(key) && !state.thumbnailOrder.includes(key))
        request(id, pixels);
    }
  }, [state.thumbnailOrder, request]);

  const onViewableItemsChanged = useCallback(
    ({ viewableItems }: { viewableItems: ViewToken<Item>[] }) => {
      const wasPinnedVisible = isPinnedVisible.current;
      isPinnedVisible.current = viewableItems.some(
        ({ item }) => item.kind === 'pinned',
      );
      visibleIds.current = viewableItems.flatMap(({ item }) =>
        item.kind === 'card' && 'clip' in item && item.clip.image !== null
          ? [item.clip.id]
          : [],
      );
      updateGrid();
      if (!wasPinnedVisible && isPinnedVisible.current) {
        for (const id of pinnedIds.current)
          request(id, current.current.pinnedPixels);
      }
    },
    [request, updateGrid],
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
