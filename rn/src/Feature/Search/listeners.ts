import { untilAborted } from '../../Shared/State/screenStore';
import type {
  SliceDispatch,
  SliceListen,
} from '../../Shared/State/screenStore';
import { showToast } from '../../Shared/UI';
import { loadSearchHistory } from '../../Service/Clip/loadSearchHistory';
import { recordSearchHistoryTerm } from '../../Service/Clip/recordSearchHistoryTerm';
import type { SearchHistoryWriteResult } from '../../Service/Clip/recordSearchHistoryTerm';
import { removeSearchHistoryTerm } from '../../Service/Clip/removeSearchHistoryTerm';
import { clearSearchHistory } from '../../Service/Clip/clearSearchHistory';
import { copyClipDetail } from '../../Service/Clip/copyDetail';
import { startClipReload } from '../ClipGrid/reload';
import { startClipThumbnailListener } from '../ClipGrid/thumbnailListener';
import { createSearchHistoryQueue } from './historyQueue';
import { searchActions as actions } from './state';
import type { SearchState } from './state';

// 기록 큐와 썸네일 큐를 비우는 정리 함수를 돌려줌
export function startSearchListeners(
  listen: SliceListen<SearchState>,
  dispatch: SliceDispatch,
  onReload: () => void,
) {
  // effect가 먼저 끝나도 큐 작업이 이어지므로 세션 단위 signal로 종료를 확인함
  const session = new AbortController();
  const queue = createSearchHistoryQueue();
  const stopThumbnails = startClipThumbnailListener(listen, dispatch, actions);
  function write(
    operation: () => Promise<SearchHistoryWriteResult>,
    isSilent = false,
  ) {
    void queue.enqueue(async () => {
      const result = await operation();
      if (session.signal.aborted) return;
      if (result.status === 'saved')
        dispatch(actions.searchHistoryLoaded(result.terms));
      else if (result.status === 'failed' && !isSilent)
        showToast('최근 검색어를 변경하지 못했습니다', false);
    });
  }
  listen({
    actionCreator: actions.viewDidLoad,
    effect: async (_, api) => {
      // 세션마다 한 번만 실행하고 abort될 때까지 구독을 소유함
      api.unsubscribe();
      void queue.enqueue(async () => {
        const result = await loadSearchHistory();
        if (session.signal.aborted) return;
        dispatch(
          result.status === 'loaded'
            ? actions.searchHistoryLoaded(result.terms)
            : actions.searchHistoryLoadFailed(),
        );
      });
      await untilAborted(api.signal, startClipReload(api, actions, onReload));
    },
  });
  listen({
    actionCreator: actions.submitQuery,
    effect: (_, api) => {
      const query = api.getState().query;
      write(() => recordSearchHistoryTerm(query));
    },
  });
  listen({
    actionCreator: actions.removeRecentTerm,
    effect: ({ payload }) => {
      write(() => removeSearchHistoryTerm(payload));
    },
  });
  listen({
    actionCreator: actions.clearRecentTerms,
    effect: () => {
      write(clearSearchHistory);
    },
  });
  listen({
    actionCreator: actions.copy,
    effect: async ({ payload }, api) => {
      const query = api.getState().query;
      const result = await copyClipDetail(payload);
      if (api.signal.aborted) return;
      const isSuccess = result === 'copied';
      showToast(
        isSuccess
          ? '클립보드에 복사했습니다'
          : '클립보드에 복사하지 못했습니다',
        isSuccess,
      );
      if (isSuccess && query !== '')
        write(() => recordSearchHistoryTerm(query), true);
    },
  });
  return () => {
    session.abort();
    queue.dispose();
    stopThumbnails();
  };
}
