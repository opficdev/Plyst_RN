import type { ClipRecord } from './clipRecord';

export function sortPinnedClips(clips: readonly ClipRecord[]): ClipRecord[] {
  return [...clips].sort((left, right) => {
    const pinned =
      (right.pinnedAt ?? right.createdAt) - (left.pinnedAt ?? left.createdAt);
    if (pinned !== 0) return pinned;
    const created = right.createdAt - left.createdAt;
    if (created !== 0) return created;
    if (left.id < right.id) return -1;
    if (right.id < left.id) return 1;
    return 0;
  });
}
