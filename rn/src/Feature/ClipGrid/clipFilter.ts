export type ClipFilter = 'all' | 'text' | 'image' | 'pinned';
export const clipFilters: readonly ClipFilter[] = [
  'all',
  'text',
  'image',
  'pinned',
];
export const clipFilterTitles = {
  all: '전체',
  text: '텍스트',
  image: '이미지',
  pinned: '고정',
} as const;
