import { removeSearchTerm } from 'plyst-bridge';

export type SearchHistoryRemoveResult =
  { status: 'saved'; terms: string[] } | { status: 'failed' };

export async function removeSearchHistoryTerm(
  term: string,
): Promise<SearchHistoryRemoveResult> {
  try {
    const terms = await removeSearchTerm(term);
    return { status: 'saved', terms };
  } catch {
    return { status: 'failed' };
  }
}
