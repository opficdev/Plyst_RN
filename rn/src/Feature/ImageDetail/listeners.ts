import { subscribeClipChanges, subscribeSave } from 'plyst-bridge';
import type { ScreenScope } from '../../Shared/State/screenStore';
import { showToast } from '../../Shared/UI';
import { copyClipDetail } from '../../Service/Clip/copyClipDetail';
import { deleteClipDetail } from '../../Service/Clip/deleteClipDetail';
import { loadImageDetail } from '../../Service/Clip/loadImageDetail';
import { createClipDetailRefresher } from '../ClipDetail/clipDetailRefresher';
import { saveImageDetail } from './saveImageDetail';
import { canSave } from './imageDetailDraft';
import type { ImageDetailState } from './imageDetailDraft';
import { imageDetailActions as actions } from './actions';
import { loadImageDetailPreview } from '../../Service/Clip/loadImageDetailPreview';
import { saveImageDetailToPhotos } from './saveImageDetailToPhotos';

export function startImageDetailListeners(
  scope: ScreenScope<ImageDetailState | null | 'closed'>,
  clipID: string,
) {
  let started = false;
  let saveSubscribed = false;
  const current = () => {
    const state = scope.getState();
    return state !== null && state !== 'closed' ? state : null;
  };
  const isStopped = () => {
    const state = scope.getState();
    return (
      scope.isDisposed() ||
      state === 'closed' ||
      !!(state?.isRemoved || state?.isSaved)
    );
  };
  const refresher = createClipDetailRefresher({
    load: () => loadImageDetail(clipID),
    onResult(result) {
      if (isStopped()) return;
      if (result.status === 'loaded') {
        scope.dispatch({ type: 'clipLoaded', clip: result.clip });
        if (!saveSubscribed) {
          saveSubscribed = true;
          const subscription = subscribeSave(() =>
            scope.dispatch(actions.save()),
          );
          scope.onDispose(() => subscription.remove());
        }
        scope.dispatch(actions.previewRequested());
      } else if (result.status === 'missing') {
        scope.dispatch({ type: 'removed' });
      } else {
        scope.dispatch({ type: 'loadFailed' });
      }
    },
  });
  scope.onDispose(() => refresher.dispose());
  scope.listen(actions.viewDidLoad, () => {
    if (started) return;
    started = true;
    const subscription = subscribeClipChanges((change) => {
      if (change.id !== clipID || isStopped()) return;
      if (change.kind === 'updated') void refresher.refresh();
      else if (change.kind === 'deleted') {
        refresher.invalidate();
        scope.dispatch({ type: 'removed' });
      }
    });
    scope.onDispose(() => subscription.remove());
    if (!isStopped()) void refresher.refresh();
  });
  scope.listen(actions.save, async () => {
    const state = current();
    if (isStopped() || !state || !canSave(state)) return;
    scope.dispatch({ type: 'saveStarted' });
    const result = await saveImageDetail(clipID, state.draft, state.clip.memo);
    // 이미 시작한 쓰기의 결과 토스트는 화면이 닫힌 뒤에도 유지합니다.
    const disposed = scope.isDisposed();
    switch (result.status) {
      case 'saved':
        if (!disposed) scope.dispatch({ type: 'saved', clip: result.clip });
        showToast('저장했습니다', true);
        break;
      case 'removed':
        if (!disposed) scope.dispatch({ type: 'removed' });
        break;
      case 'failed':
        if (!disposed) scope.dispatch({ type: 'saveFailed' });
        showToast('저장하지 못했습니다', false);
        break;
    }
  });
  scope.listen(actions.copy, async () => {
    const state = current();
    if (!state || state.isDeleting || state.isRemoved) return;
    const result = await copyClipDetail(clipID);
    // 복사 결과는 화면 수명과 관계없이 기존 토스트 창에 표시합니다.
    showToast(
      result === 'copied'
        ? '클립보드에 복사했습니다'
        : '클립보드에 복사하지 못했습니다',
      result === 'copied',
    );
  });
  scope.listen(actions.delete, async () => {
    const state = current();
    if (!state || state.isDeleting || state.isRemoved) return;
    scope.dispatch({ type: 'deleteStarted' });
    const result = await deleteClipDetail(clipID);
    if (!scope.isDisposed())
      scope.dispatch({
        type: result === 'deleted' ? 'removed' : 'deleteFailed',
      });
    if (result === 'failed') showToast('삭제하지 못했습니다', false);
  });
  let previewRequested = false;
  scope.listen(actions.previewRequested, async () => {
    if (previewRequested || isStopped()) return;
    previewRequested = true;
    const preview = await loadImageDetailPreview(clipID);
    if (isStopped()) return;
    scope.dispatch(
      preview.status === 'loaded'
        ? { type: 'previewReady', uri: preview.uri }
        : { type: 'previewFailed' },
    );
  });
  scope.listen(actions.saveToPhotos, async () => {
    const state = current();
    if (!state || state.isSavingToPhotos || state.isDeleting || state.isRemoved)
      return;
    scope.dispatch({ type: 'photoSaveStarted' });
    const result = await saveImageDetailToPhotos(clipID);
    if (!scope.isDisposed())
      scope.dispatch({
        type: result.status === 'removed' ? 'removed' : 'photoSaveFinished',
      });
    if (result.status !== 'removed')
      showToast(result.message, result.isSuccess);
  });
}
