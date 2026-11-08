import { edgeWhitespace } from './clipWhitespace';

export function normalizedName(draft: { name: string }): string | null {
  return draft.name.replace(edgeWhitespace, '') || null;
}

export function normalizedMemo(draft: { memo: string }): string | null {
  return draft.memo.replace(edgeWhitespace, '') === '' ? null : draft.memo;
}

export function equivalent(left: string | null, right: string | null): boolean {
  if (left === null || right === null) return left === right;
  return left.normalize('NFC') === right.normalize('NFC');
}
