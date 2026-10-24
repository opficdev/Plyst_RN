import { subscribeClipChanges } from 'plyst-bridge';
import { untilAborted } from '../../Shared/State/screenStore';
import type { SliceListen } from '../../Shared/State/screenStore';
import { showToast } from '../../Shared/UI';
import { copyClipDetail } from '../../Service/Clip/copyDetail';
import { deleteClipDetail } from '../../Service/Clip/deleteDetail';
import { loadImageDetail } from '../../Service/Clip/loadImageDetail';
import { loadImageDetailPreview } from '../../Service/Clip/loadImageDetailPreview';
import { createClipDetailRefresher } from '../ClipDetail/refresher';
import { saveImageDetail } from './save';
import { saveImageDetailToPhotos } from './saveToPhotos';
import {
  canStartDelete,
  canStartPhotoSave,
  canStartSave,
  imageDetailActions as actions,
  isClosed,
} from './draft';
import type { ImageDetailStoreState } from './draft';

export function startImageDetailListeners(
  listen: SliceListen<ImageDetailStoreState>,
  clipID: string,
) {
  listen({
    actionCreator: actions.viewDidLoad,
    effect: async (_, api) => {
      // 세션마다 한 번만 실행하고 abort될 때까지 구독을 소유함
      api.unsubscribe();
      const isStopped = () => api.signal.aborted || isClosed(api.getState());
      const refresher = createClipDetailRefresher({
        load: () => loadImageDetail(clipID),
        onResult(result) {
          if (isStopped()) return;
          if (result.status === 'loaded') {
            api.dispatch(actions.clipLoaded(result.clip));
            api.dispatch(actions.previewRequested());
          } else if (result.status === 'missing') {
            api.dispatch(actions.removed());
          } else {
            api.dispatch(actions.loadFailed());
          }
        },
      });
      const subscription = subscribeClipChanges((change) => {
        if (change.id !== clipID || isStopped()) return;
        if (change.kind === 'updated') void refresher.refresh();
        else if (change.kind === 'deleted') {
          refresher.invalidate();
          api.dispatch(actions.removed());
        }
      });
      const aborted = untilAborted(api.signal, () => {
        subscription.remove();
        refresher.dispose();
      });
      if (!isStopped()) void refresher.refresh();
      await aborted;
    },
  });
  listen({
    actionCreator: actions.save,
    effect: async (_, api) => {
      const before = api.getOriginalState();
      if (!canStartSave(before)) return;
      const result = await saveImageDetail(
        clipID,
        before.draft,
        before.clip.memo,
      );
      // 이미 시작한 쓰기의 결과 토스트는 화면이 닫힌 뒤에도 유지함
      const isActive = !api.signal.aborted;
      switch (result.status) {
        case 'saved':
          if (isActive) api.dispatch(actions.saved(result.clip));
          showToast('저장했습니다', true);
          break;
        case 'removed':
          if (isActive) api.dispatch(actions.removed());
          break;
        case 'failed':
          if (isActive) api.dispatch(actions.saveFailed());
          showToast('저장하지 못했습니다', false);
          break;
      }
    },
  });
  listen({
    actionCreator: actions.copy,
    effect: async (_, api) => {
      const state = api.getState();
      if (state.phase !== 'loaded' || state.isDeleting || state.isRemoved) {
        return;
      }
      const result = await copyClipDetail(clipID);
      // 복사 결과는 화면 수명과 관계없이 기존 토스트 창에 표시함
      showToast(
        result === 'copied'
          ? '클립보드에 복사했습니다'
          : '클립보드에 복사하지 못했습니다',
        result === 'copied',
      );
    },
  });
  listen({
    actionCreator: actions.delete,
    effect: async (_, api) => {
      if (!canStartDelete(api.getOriginalState())) return;
      const result = await deleteClipDetail(clipID);
      if (!api.signal.aborted) {
        api.dispatch(
          result === 'deleted' ? actions.removed() : actions.deleteFailed(),
        );
      }
      if (result === 'failed') showToast('삭제하지 못했습니다', false);
    },
  });
  listen({
    actionCreator: actions.previewRequested,
    effect: async (_, api) => {
      // 중단된 화면은 다시 살아나지 않으므로 그대로 끝냄
      if (api.signal.aborted || isClosed(api.getState())) return;
      api.unsubscribe();
      const preview = await loadImageDetailPreview(clipID);
      if (api.signal.aborted || isClosed(api.getState())) return;
      api.dispatch(
        preview.status === 'loaded'
          ? actions.previewReady(preview.uri)
          : actions.previewFailed(),
      );
    },
  });
  listen({
    actionCreator: actions.saveToPhotos,
    effect: async (_, api) => {
      if (!canStartPhotoSave(api.getOriginalState())) return;
      const result = await saveImageDetailToPhotos(clipID);
      if (!api.signal.aborted) {
        api.dispatch(
          result.status === 'removed'
            ? actions.removed()
            : actions.photoSaveFinished(),
        );
      }
      if (result.status !== 'removed') {
        showToast(result.message, result.isSuccess);
      }
    },
  });
}
