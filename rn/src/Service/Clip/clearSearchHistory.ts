import { removeAllSearchTerms } from 'plyst-bridge';

export type SearchHistoryClearResult =
  { status: 'saved'; terms: string[] } | { status: 'failed' };

export async function clearSearchHistory(): Promise<SearchHistoryClearResult> {
  try {
    await removeAllSearchTerms();
    return { status: 'saved', terms: [] };
  } catch {
    return { status: 'failed' };
  }
}
