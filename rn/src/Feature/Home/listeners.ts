import {
  subscribeClipboardSaveRequests,
  subscribeSearchVisibility,
} from 'plyst-bridge';
import type { ScreenScope } from '../../Shared/State/screenStore';
import { showToast } from '../../Shared/UI';
import { copyClipDetail } from '../../Service/Clip/copyDetail';
import { deleteClipDetail } from '../../Service/Clip/deleteDetail';
import { updateClipDetail } from '../../Service/Clip/updateDetail';
import { startClipReload } from '../ClipGrid/reload';
import { startClipThumbnailListener } from '../ClipGrid/thumbnailListener';
import { saveHomeClipboard } from './saveClipboard';
import { homePinTarget } from './menu';
import type { HomeState } from './state';
import { homeActions as actions } from './actions';

export function startHomeListeners(scope: ScreenScope<HomeState>) {
  startClipThumbnailListener(scope);
  let started = false;
  let deleting = false;
  scope.listen(actions.viewDidLoad, () => {
    if (started) return;
    started = true;
    // ready()가 보관한 저장 요청을 전달하기 전에 저장 listener를 등록합니다.
    const saves = subscribeClipboardSaveRequests(() =>
      scope.dispatch(actions.saveCurrentClipboard()),
    );
    scope.onDispose(() => saves.remove());
    startClipReload(scope);
    const visibility = subscribeSearchVisibility((isVisible) => {
      scope.dispatch({ type: 'searchVisibilityChanged', isVisible });
    });
    scope.onDispose(() => visibility.remove());
  });
  scope.listen(actions.saveCurrentClipboard, async () => {
    if (scope.getState().isSaving) return;
    scope.dispatch({ type: 'savingStarted' });
    const result = await saveHomeClipboard();
    showToast(result.message, result.isSuccess);
    if (!scope.isDisposed()) scope.dispatch({ type: 'savingStopped' });
  });
  scope.listen(actions.copy, async ({ payload }) => {
    const result = await copyClipDetail(payload);
    showToast(
      result === 'copied'
        ? '클립보드에 복사했습니다'
        : '클립보드에 복사하지 못했습니다',
      result === 'copied',
    );
  });
  scope.listen(actions.setPinned, async () => {
    const current = scope.getState();
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
  });
  scope.listen(actions.delete, async () => {
    const current = scope.getState();
    const clip = current.clips.find((clip) => clip.id === current.menuClip?.id);
    if (!clip || deleting) return;
    deleting = true;
    const result = await deleteClipDetail(clip.id);
    deleting = false;
    if (result === 'failed') showToast('삭제하지 못했습니다', false);
  });
}
