import type { SliceListen } from '../../Shared/State/screenStore';
import { loadClipThumbnail } from '../../Service/Clip/loadThumbnail';
import { clipGridActions as actions } from './actions';
import type { ClipGridAction } from './actions';
import { createThumbnailRequestQueue } from './thumbnailRequests';

// 요청 큐를 만들고 세션이 끝날 때 큐를 비우는 정리 함수를 돌려줍니다.
export function startClipThumbnailListener<State>(
  listen: SliceListen<State>,
  dispatch: (action: ClipGridAction) => unknown,
) {
  const queue = createThumbnailRequestQueue({
    load: loadClipThumbnail,
    onStarted: (key) => dispatch(actions.thumbnailStarted(key)),
    onLoaded: (key, uri) => dispatch(actions.thumbnailLoaded({ key, uri })),
    onFailed: (key) => dispatch(actions.thumbnailFailed(key)),
    onCancelled: (key) => dispatch(actions.thumbnailCancelled(key)),
  });
  listen({
    actionCreator: actions.thumbnailRequested,
    effect: ({ payload }) => {
      queue.request(payload.id, payload.pixels);
    },
  });
  listen({
    actionCreator: actions.thumbnailCancelRequested,
    effect: ({ payload }) => {
      queue.cancel(payload.id, payload.pixels);
    },
  });
  return () => queue.dispose();
}
