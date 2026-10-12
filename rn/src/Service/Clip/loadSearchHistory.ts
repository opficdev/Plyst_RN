import { getSearchHistory } from 'plyst-bridge';

export type SearchHistoryLoadResult =
  { status: 'loaded'; terms: string[] } | { status: 'failed' };

export async function loadSearchHistory(): Promise<SearchHistoryLoadResult> {
  try {
    const terms = await getSearchHistory();
    return { status: 'loaded', terms };
  } catch {
    return { status: 'failed' };
  }
}
