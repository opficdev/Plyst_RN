import type { ScreenScope } from '../../Shared/State/screenStore';
import { showToast } from '../../Shared/UI';
import { loadSearchHistory } from '../../Service/Clip/loadSearchHistory';
import { recordSearchHistoryTerm } from '../../Service/Clip/recordSearchHistoryTerm';
import type { SearchHistoryWriteResult } from '../../Service/Clip/recordSearchHistoryTerm';
import { removeSearchHistoryTerm } from '../../Service/Clip/removeSearchHistoryTerm';
import { clearSearchHistory } from '../../Service/Clip/clearSearchHistory';
import { copyClipDetail } from '../../Service/Clip/copyClipDetail';
import { startClipReload } from '../ClipGrid/reload';
import { startClipThumbnailListener } from '../ClipGrid/thumbnailListener';
import { createSearchHistoryQueue } from './searchHistoryQueue';
import type { SearchState } from './searchState';
import { searchActions as actions } from './actions';

export function startSearchListeners(
  scope: ScreenScope<SearchState>,
  onReload: () => void,
) {
  const queue = createSearchHistoryQueue();
  scope.onDispose(() => queue.dispose());
  startClipThumbnailListener(scope);
  let started = false;
  function write(
    operation: () => Promise<SearchHistoryWriteResult>,
    isSilent = false,
  ) {
    void queue.enqueue(async () => {
      const result = await operation();
      if (scope.isDisposed()) return;
      if (result.status === 'saved')
        scope.dispatch({ type: 'searchHistoryLoaded', terms: result.terms });
      else if (result.status === 'failed' && !isSilent)
        showToast('최근 검색어를 변경하지 못했습니다', false);
    });
  }
  scope.listen(actions.viewDidLoad, () => {
    if (started) return;
    started = true;
    void queue.enqueue(async () => {
      const result = await loadSearchHistory();
      if (scope.isDisposed()) return;
      scope.dispatch(
        result.status === 'loaded'
          ? { type: 'searchHistoryLoaded', terms: result.terms }
          : { type: 'searchHistoryLoadFailed' },
      );
    });
    startClipReload(scope, onReload);
  });
  scope.listen(actions.submitQuery, () => {
    const query = scope.getState().query;
    write(() => recordSearchHistoryTerm(query));
  });
  scope.listen(actions.removeRecentTerm, ({ payload }) => {
    write(() => removeSearchHistoryTerm(payload));
  });
  scope.listen(actions.clearRecentTerms, () => write(clearSearchHistory));
  scope.listen(actions.copy, async ({ payload }) => {
    const query = scope.getState().query;
    const result = await copyClipDetail(payload);
    if (scope.isDisposed()) return;
    const isSuccess = result === 'copied';
    showToast(
      isSuccess ? '클립보드에 복사했습니다' : '클립보드에 복사하지 못했습니다',
      isSuccess,
    );
    if (isSuccess && query !== '')
      write(() => recordSearchHistoryTerm(query), true);
  });
}
