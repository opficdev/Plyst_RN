import { recordSearchTerm } from 'plyst-bridge';

export type SearchHistoryWriteResult =
  | { status: 'saved'; terms: string[] }
  | { status: 'unchanged' }
  | { status: 'failed' };

export async function recordSearchHistoryTerm(
  term: string,
): Promise<SearchHistoryWriteResult> {
  try {
    const terms = await recordSearchTerm(term);
    return terms === null
      ? { status: 'unchanged' }
      : { status: 'saved', terms };
  } catch {
    return { status: 'failed' };
  }
}
