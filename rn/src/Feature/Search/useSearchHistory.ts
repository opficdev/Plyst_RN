import { useCallback, useEffect, useRef } from 'react';
import type { Dispatch } from 'react';
import {
  getSearchHistory,
  recordSearchTerm,
  removeSearchTerm,
  removeAllSearchTerms,
} from 'plyst-bridge';
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
      try {
        const terms = await getSearchHistory();
        if (!disposed) dispatch({ type: 'searchHistoryLoaded', terms });
      } catch {
        if (!disposed) dispatch({ type: 'searchHistoryLoadFailed' });
      }
    });
    return () => {
      disposed = true;
      operations.dispose();
      queue.current = null;
    };
  }, [dispatch]);

  const write = useCallback(
    (operation: () => Promise<string[] | null>, isSilent = false) => {
      const operations = queue.current;
      void operations?.enqueue(async () => {
        try {
          const terms = await operation();
          if (queue.current === operations && terms !== null)
            dispatch({ type: 'searchHistoryLoaded', terms });
        } catch {
          if (queue.current === operations && !isSilent)
            showToast('최근 검색어를 변경하지 못했습니다', false);
        }
      });
    },
    [dispatch],
  );
  return {
    record: (term: string, isSilent = false) =>
      write(() => recordSearchTerm(term), isSilent),
    remove: (term: string) => write(() => removeSearchTerm(term)),
    clear: () =>
      write(async () => {
        await removeAllSearchTerms();
        return [];
      }),
  };
}
