import { useCallback, useEffect, useRef } from 'react';
import type { Dispatch } from 'react';
import { loadSearchHistory } from '../../Service/Clip/loadSearchHistory';
import { recordSearchHistoryTerm } from '../../Service/Clip/recordSearchHistoryTerm';
import type { SearchHistoryWriteResult } from '../../Service/Clip/recordSearchHistoryTerm';
import { removeSearchHistoryTerm } from '../../Service/Clip/removeSearchHistoryTerm';
import { clearSearchHistory } from '../../Service/Clip/clearSearchHistory';
import { showToast } from '../../Shared/UI';
import { createSearchHistoryQueue } from './searchHistoryQueue';
import type { SearchAction } from './searchState';

export function useSearchHistory(dispatch: Dispatch<SearchAction>) {
  const queue = useRef<ReturnType<typeof createSearchHistoryQueue> | null>(
    null,
  );
  useEffect(() => {
    const operations = createSearchHistoryQueue();
    queue.current = operations;
    let disposed = false;
    void operations.enqueue(async () => {
      const result = await loadSearchHistory();
      if (disposed) return;
      dispatch(
        result.status === 'loaded'
          ? { type: 'searchHistoryLoaded', terms: result.terms }
          : { type: 'searchHistoryLoadFailed' },
      );
    });
    return () => {
      disposed = true;
      operations.dispose();
      queue.current = null;
    };
  }, [dispatch]);

  const write = useCallback(
    (operation: () => Promise<SearchHistoryWriteResult>, isSilent = false) => {
      const operations = queue.current;
      void operations?.enqueue(async () => {
        const result = await operation();
        if (queue.current !== operations) return;
        if (result.status === 'saved')
          dispatch({ type: 'searchHistoryLoaded', terms: result.terms });
        else if (result.status === 'failed' && !isSilent)
          showToast('최근 검색어를 변경하지 못했습니다', false);
      });
    },
    [dispatch],
  );
  return {
    record: (term: string, isSilent = false) =>
      write(() => recordSearchHistoryTerm(term), isSilent),
    remove: (term: string) => write(() => removeSearchHistoryTerm(term)),
    clear: () => write(clearSearchHistory),
  };
}
