import type { ClipRecord } from 'plyst-bridge';

export const clipThumbnailLimit = 48;
export type ClipThumbnails = {
  thumbnails: Record<string, string>;
  thumbnailOrder: string[];
  loadingThumbnails: Record<string, true>;
  failedThumbnails: Record<string, true>;
};
export type ClipThumbnailAction =
  | { type: 'thumbnailStarted'; key: string }
  | { type: 'thumbnailLoaded'; key: string; uri: string }
  | { type: 'thumbnailFailed'; key: string }
  | { type: 'thumbnailCancelled'; key: string };

function clipID(key: string): string {
  return key.slice(0, key.lastIndexOf(':'));
}

export function retainClipThumbnails(
  state: ClipThumbnails,
  clips: ClipRecord[],
): ClipThumbnails {
  const next = { ...state };
  const valid = new Set(
    clips.filter((clip) => clip.image !== null).map((clip) => clip.id),
  );
  const retained = (key: string) => valid.has(clipID(key));
  next.thumbnails = Object.fromEntries(
    Object.entries(next.thumbnails).filter(([key]) => retained(key)),
  );
  next.thumbnailOrder = next.thumbnailOrder.filter(retained);
  next.loadingThumbnails = Object.fromEntries(
    Object.entries(next.loadingThumbnails).filter(([key]) => retained(key)),
  );
  next.failedThumbnails = Object.fromEntries(
    Object.entries(next.failedThumbnails).filter(([key]) => retained(key)),
  );
  return next;
}

export function reduceClipThumbnails(
  state: ClipThumbnails,
  action: ClipThumbnailAction,
  clips: ClipRecord[],
): ClipThumbnails {
  const next = {
    thumbnails: { ...state.thumbnails },
    thumbnailOrder: [...state.thumbnailOrder],
    loadingThumbnails: { ...state.loadingThumbnails },
    failedThumbnails: { ...state.failedThumbnails },
  };
  switch (action.type) {
    case 'thumbnailStarted':
      next.loadingThumbnails[action.key] = true;
      break;
    case 'thumbnailLoaded': {
      const wasLoading = next.loadingThumbnails[action.key];
      delete next.loadingThumbnails[action.key];
      if (
        !wasLoading ||
        !clips.some(
          (clip) => clip.id === clipID(action.key) && clip.image !== null,
        )
      )
        break;
      next.thumbnails[action.key] = action.uri;
      next.thumbnailOrder = next.thumbnailOrder.filter(
        (key) => key !== action.key,
      );
      next.thumbnailOrder.push(action.key);
      while (clipThumbnailLimit < next.thumbnailOrder.length) {
        const oldest = next.thumbnailOrder.shift()!;
        delete next.thumbnails[oldest];
      }
      break;
    }
    case 'thumbnailFailed':
      delete next.loadingThumbnails[action.key];
      next.failedThumbnails[action.key] = true;
      break;
    case 'thumbnailCancelled':
      delete next.loadingThumbnails[action.key];
      break;
  }
  return next;
}
