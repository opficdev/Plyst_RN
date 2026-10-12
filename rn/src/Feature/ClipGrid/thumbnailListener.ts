import { createAction } from '../../Shared/State/screenStore';
import type { ScreenScope } from '../../Shared/State/screenStore';
import { loadClipThumbnail } from '../../Service/Clip/loadClipThumbnail';
import { createThumbnailRequestQueue } from './clipThumbnailRequests';

export const clipThumbnailActions = {
  thumbnailRequested: createAction<{ id: string; pixels: number }>(
    'action/thumbnailRequested',
  ),
  thumbnailCancelled: createAction<{ id: string; pixels: number }>(
    'action/thumbnailCancelled',
  ),
};

export function startClipThumbnailListener<State>(scope: ScreenScope<State>) {
  const queue = createThumbnailRequestQueue({
    load: loadClipThumbnail,
    onStarted: (key) => scope.dispatch({ type: 'thumbnailStarted', key }),
    onLoaded: (key, uri) =>
      scope.dispatch({ type: 'thumbnailLoaded', key, uri }),
    onFailed: (key) => scope.dispatch({ type: 'thumbnailFailed', key }),
    onCancelled: (key) => scope.dispatch({ type: 'thumbnailCancelled', key }),
  });
  scope.onDispose(() => queue.dispose());
  scope.listen(clipThumbnailActions.thumbnailRequested, ({ payload }) => {
    queue.request(payload.id, payload.pixels);
  });
  scope.listen(clipThumbnailActions.thumbnailCancelled, ({ payload }) => {
    queue.cancel(payload.id, payload.pixels);
  });
}
