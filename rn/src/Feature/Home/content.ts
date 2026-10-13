import { clipFilterTitles } from '../ClipGrid/filter';
import type { ClipFilter } from '../ClipGrid/filter';
import { clipSectionKind, clipSectionKinds } from '../ClipGrid/section';
import type { ClipSectionKind } from '../ClipGrid/section';
import type { ClipLoadPhase } from '../ClipGrid/loadPhase';
import type { ClipRecord } from '../../Model/clipRecord';

export const homeFilterStrings = {
  all: {
    title: clipFilterTitles.all,
    emptyTitle: '아직 저장된 내용이 없습니다',
    emptyMessage: '텍스트나 이미지를 복사한 뒤 현재 클립보드 저장을 눌러보세요',
  },
  text: {
    title: clipFilterTitles.text,
    emptyTitle: '저장된 텍스트가 없습니다',
    emptyMessage: '텍스트를 복사한 뒤 현재 클립보드 저장을 눌러보세요',
  },
  image: {
    title: clipFilterTitles.image,
    emptyTitle: '저장된 이미지가 없습니다',
    emptyMessage: '이미지를 복사한 뒤 현재 클립보드 저장을 눌러보세요',
  },
  pinned: {
    title: clipFilterTitles.pinned,
    emptyTitle: '고정한 항목이 없습니다',
    emptyMessage: '항목을 길게 눌러 고정할 수 있어요',
  },
} as const;

export type HomeSection = { kind: ClipSectionKind; clips: ClipRecord[] };
export type HomeContent = {
  pinnedClips: ClipRecord[];
  sections: HomeSection[];
  isEmpty: boolean;
};

export function makeHomeContent(
  clips: ClipRecord[],
  filter: ClipFilter,
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
  const groups: Record<ClipSectionKind, ClipRecord[]> = {
    recent: [],
    today: [],
    yesterday: [],
    earlier: [],
  };
  for (const clip of timeline) {
    const kind = clipSectionKind(clip.createdAt, now);
    groups[kind].push(clip);
  }
  const sections = clipSectionKinds
    .filter((kind) => groups[kind].length !== 0)
    .map((kind) => ({ kind, clips: groups[kind] }));
  return {
    pinnedClips,
    sections,
    isEmpty: pinnedClips.length === 0 && sections.length === 0,
  };
}

export type HomeEmptyState = 'none' | 'empty' | 'filtered' | 'failed';

export function homeEmptyState({
  loadPhase,
  clips,
  content,
}: {
  loadPhase: ClipLoadPhase;
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
