const edgeWhitespace =
  /^[\t\n\v\f\r\u0020\u0085\u00A0\u1680\u2000-\u200A\u2028\u2029\u202F\u205F\u3000]+|[\t\n\v\f\r\u0020\u0085\u00A0\u1680\u2000-\u200A\u2028\u2029\u202F\u205F\u3000]+$/g;

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
