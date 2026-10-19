import { subscribeClipboardSaveRequests } from 'plyst-bridge';
import { untilAborted } from '../../Shared/State/screenStore';
import type { SliceListen } from '../../Shared/State/screenStore';
import { showToast } from '../../Shared/UI';
import { copyClipDetail } from '../../Service/Clip/copyDetail';
import { deleteClipDetail } from '../../Service/Clip/deleteDetail';
import { updateClipDetail } from '../../Service/Clip/updateDetail';
import type { ClipGridAction } from '../ClipGrid/actions';
import { startClipReload } from '../ClipGrid/reload';
import { startClipThumbnailListener } from '../ClipGrid/thumbnailListener';
import { saveHomeClipboard } from './saveClipboard';
import { homePinTarget } from './menu';
import { homeActions as actions } from './state';
import type { HomeState } from './state';

// 썸네일 큐를 비우는 정리 함수를 돌려줍니다.
export function startHomeListeners(
  listen: SliceListen<HomeState>,
  dispatch: (action: ClipGridAction) => unknown,
) {
  const stopThumbnails = startClipThumbnailListener(listen, dispatch);
  let deleting = false;
  listen({
    actionCreator: actions.viewDidLoad,
    effect: async (_, api) => {
      // 세션마다 한 번만 실행하고 abort될 때까지 구독을 소유합니다.
      api.unsubscribe();
      // ready()가 보관한 저장 요청을 전달하기 전에 저장 listener를 등록합니다.
      const saves = subscribeClipboardSaveRequests(() =>
        api.dispatch(actions.saveCurrentClipboard()),
      );
      const stopReload = startClipReload(api);
      await untilAborted(api.signal, () => {
        stopReload();
        saves.remove();
      });
    },
  });
  listen({
    actionCreator: actions.saveCurrentClipboard,
    effect: async (_, api) => {
      if (api.getOriginalState().isSaving) return;
      const result = await saveHomeClipboard();
      showToast(result.message, result.isSuccess);
      if (!api.signal.aborted) api.dispatch(actions.savingStopped());
    },
  });
  listen({
    actionCreator: actions.copy,
    effect: async ({ payload }) => {
      const result = await copyClipDetail(payload);
      showToast(
        result === 'copied'
          ? '클립보드에 복사했습니다'
          : '클립보드에 복사하지 못했습니다',
        result === 'copied',
      );
    },
  });
  listen({
    actionCreator: actions.setPinned,
    effect: async (_, api) => {
      const current = api.getState();
      const menuClip = current.menuClip;
      if (!menuClip) return;
      const clip = current.clips.find((clip) => clip.id === menuClip.id);
      const target = homePinTarget(menuClip, clip);
      if (target === null || !clip) return;
      const result = await updateClipDetail(
        clip.id,
        clip.name,
        clip.memo,
        target,
      );
      if (result.status !== 'saved')
        showToast('고정 상태를 바꾸지 못했습니다', false);
    },
  });
  listen({
    actionCreator: actions.delete,
    effect: async (_, api) => {
      const current = api.getState();
      const clip = current.clips.find(
        (clip) => clip.id === current.menuClip?.id,
      );
      if (!clip || deleting) return;
      deleting = true;
      const result = await deleteClipDetail(clip.id);
      deleting = false;
      if (result === 'failed') showToast('삭제하지 못했습니다', false);
    },
  });
  return stopThumbnails;
}
