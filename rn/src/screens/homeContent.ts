import type { ClipRecord } from 'plyst-bridge';

export type HomeFilter = 'all' | 'text' | 'image' | 'pinned';
export const homeFilters: readonly HomeFilter[] = [
  'all',
  'text',
  'image',
  'pinned',
];
export const homeFilterStrings = {
  all: {
    title: '전체',
    emptyTitle: '아직 저장된 내용이 없습니다',
    emptyMessage: '텍스트나 이미지를 복사한 뒤 현재 클립보드 저장을 눌러보세요',
  },
  text: {
    title: '텍스트',
    emptyTitle: '저장된 텍스트가 없습니다',
    emptyMessage: '텍스트를 복사한 뒤 현재 클립보드 저장을 눌러보세요',
  },
  image: {
    title: '이미지',
    emptyTitle: '저장된 이미지가 없습니다',
    emptyMessage: '이미지를 복사한 뒤 현재 클립보드 저장을 눌러보세요',
  },
  pinned: {
    title: '고정',
    emptyTitle: '고정한 항목이 없습니다',
    emptyMessage: '항목을 길게 눌러 고정할 수 있어요',
  },
} as const;

export type HomeSectionKind = 'recent' | 'today' | 'yesterday' | 'earlier';
export const homeSectionKinds: readonly HomeSectionKind[] = [
  'recent',
  'today',
  'yesterday',
  'earlier',
];
export const homeSectionTitles = {
  recent: '방금',
  today: '오늘',
  yesterday: '어제',
  earlier: '이전',
} as const;
export type HomeSection = { kind: HomeSectionKind; clips: ClipRecord[] };
export type HomeContent = {
  pinnedClips: ClipRecord[];
  sections: HomeSection[];
  isEmpty: boolean;
};

export function makeHomeContent(
  clips: ClipRecord[],
  filter: HomeFilter,
  now: number,
): HomeContent {
  const pinnedClips =
    filter === 'all' ? clips.filter((clip) => clip.isPinned) : [];
  const timeline = clips.filter((clip) => {
    switch (filter) {
      case 'all':
        return !clip.isPinned;
      case 'text':
        return clip.text !== null;
      case 'image':
        return clip.image !== null;
      case 'pinned':
        return clip.isPinned;
    }
  });
  const today = new Date(now);
  today.setHours(0, 0, 0, 0);
  const yesterday = new Date(today);
  yesterday.setDate(yesterday.getDate() - 1);
  const groups: Record<HomeSectionKind, ClipRecord[]> = {
    recent: [],
    today: [],
    yesterday: [],
    earlier: [],
  };
  for (const clip of timeline) {
    // 자정과 미래 시각에 관계없이 최근 5분 구간을 먼저 판별합니다.
    const kind =
      now - 300_000 < clip.createdAt
        ? 'recent'
        : today.getTime() <= clip.createdAt
          ? 'today'
          : yesterday.getTime() <= clip.createdAt
            ? 'yesterday'
            : 'earlier';
    groups[kind].push(clip);
  }
  const sections = homeSectionKinds
    .filter((kind) => groups[kind].length !== 0)
    .map((kind) => ({ kind, clips: groups[kind] }));
  return {
    pinnedClips,
    sections,
    isEmpty: pinnedClips.length === 0 && sections.length === 0,
  };
}

export type HomeLoadPhase = 'loading' | 'loaded' | 'failed';
export type HomeEmptyState = 'none' | 'empty' | 'filtered' | 'failed';

export function homeEmptyState({
  loadPhase,
  clips,
  content,
}: {
  loadPhase: HomeLoadPhase;
  clips: ClipRecord[];
  content: HomeContent;
}): HomeEmptyState {
  // 전체 목록이 비었으면 content의 빈 상태보다 우선합니다.
  switch (loadPhase) {
    case 'loading':
      return 'none';
    case 'loaded':
      if (clips.length === 0) return 'empty';
      return content.isEmpty ? 'filtered' : 'none';
    case 'failed':
      return clips.length === 0 ? 'failed' : 'none';
  }
}
