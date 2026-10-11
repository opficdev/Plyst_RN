export type ClipSectionKind = 'recent' | 'today' | 'yesterday' | 'earlier';
export const clipSectionKinds: readonly ClipSectionKind[] = [
  'recent',
  'today',
  'yesterday',
  'earlier',
];
export const clipSectionTitles = {
  recent: '방금',
  today: '오늘',
  yesterday: '어제',
  earlier: '이전',
} as const;

export function clipSectionKind(
  createdAt: number,
  now: number,
): ClipSectionKind {
  const today = new Date(now);
  today.setHours(0, 0, 0, 0);
  const yesterday = new Date(today);
  yesterday.setDate(yesterday.getDate() - 1);
  return now - 300_000 < createdAt
    ? 'recent'
    : today.getTime() <= createdAt
      ? 'today'
      : yesterday.getTime() <= createdAt
        ? 'yesterday'
        : 'earlier';
}
