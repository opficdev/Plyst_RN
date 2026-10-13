import type { ClipRecord } from '../../Model/clipRecord';
import type { ClipFilter } from '../ClipGrid/filter';
import type { ClipLoadPhase } from '../ClipGrid/loadPhase';
import { clipSectionKind, clipSectionTitles } from '../ClipGrid/section';
import { formatClipCardTime } from '../ClipGrid/cardFormat';
import { clusters } from '../../Model/clipText';
import { normalizeSearchQuery } from './match';
import type { SearchIndex } from './match';

export type SearchContent = {
  query: string;
  results: ClipRecord[];
  textCount: number;
  imageCount: number;
};

export function createSearchTimeTexts() {
  let currentNow: number | undefined;
  const cache = new Map<string, { createdAt: number; texts: string[] }>();
  return {
    retain(clips: ClipRecord[]) {
      const valid = new Set(clips.map((clip) => clip.id));
      for (const id of cache.keys()) if (!valid.has(id)) cache.delete(id);
    },
    texts(clip: ClipRecord, now: number) {
      if (currentNow !== now) {
        cache.clear();
        currentNow = now;
      }
      const cached = cache.get(clip.id);
      if (cached?.createdAt === clip.createdAt) return cached.texts;
      const section = clipSectionTitles[clipSectionKind(clip.createdAt, now)];
      const texts = [
        `${section} ${formatClipCardTime(clip.createdAt, now)}`,
        new Intl.DateTimeFormat(undefined, { dateStyle: 'medium' }).format(
          new Date(clip.createdAt),
        ),
      ];
      cache.set(clip.id, { createdAt: clip.createdAt, texts });
      return texts;
    },
  };
}

export function makeSearchContent(
  clips: ClipRecord[],
  rawQuery: string,
  filter: ClipFilter,
  now: number,
  index: SearchIndex,
  times: ReturnType<typeof createSearchTimeTexts>,
): SearchContent {
  const query = normalizeSearchQuery(rawQuery);
  const results = !query
    ? []
    : clips.filter((clip) => {
        if (filter === 'text' && clip.text === null) return false;
        if (filter === 'image' && clip.image === null) return false;
        if (filter === 'pinned' && clip.pinnedAt === null) return false;
        if (index.matches(clip.id, 'name', clip.name ?? '', query)) return true;
        if (clip.image === null)
          return index.matches(clip.id, 'body', clip.text ?? '', query);
        return times
          .texts(clip, now)
          .some((text, position) =>
            index.matches(clip.id, `time:${position}`, text, query),
          );
      });
  return {
    query,
    results,
    textCount: results.filter((clip) => clip.text !== null).length,
    imageCount: results.filter((clip) => clip.image !== null).length,
  };
}

export function searchHeaderTitle(content: SearchContent): string {
  const title = `결과 ${content.results.length}개`;
  return content.textCount !== 0 && content.imageCount !== 0
    ? `${title} · 텍스트 ${content.textCount} · 이미지 ${content.imageCount}`
    : title;
}

export function searchMode(
  content: SearchContent,
  loadPhase: ClipLoadPhase,
  clips: ClipRecord[],
): 'recent' | 'results' | 'empty' | 'failed' {
  if (!content.query) return 'recent';
  if (loadPhase === 'loading') return 'results';
  if (loadPhase === 'failed' && clips.length === 0) return 'failed';
  return content.results.length === 0 ? 'empty' : 'results';
}

export function searchEmptyStrings(
  query: string,
  filter: ClipFilter,
  isFailed: boolean,
) {
  return isFailed
    ? {
        title: '기록을 불러오지 못했습니다',
        message: '앱을 다시 열어 기록을 확인해 주세요',
      }
    : {
        title: `‘${query}’ 결과 없음`,
        message:
          filter === 'all'
            ? '이미지는 이름과 저장 시각으로만 찾을 수 있어요.'
            : '필터를 ‘전체’로 바꾸거나 다른 단어로 검색해 보세요.',
      };
}

export function searchExcerptStart(body: string, location: number): number {
  const letters = clusters(body);
  const position = letters.findIndex((letter) => letter.index === location);
  return 40 < position ? letters[position - 14].index : 0;
}

export function searchRecentDisplay(
  phase: 'initial' | 'loaded' | 'failed',
  terms: string[],
) {
  if (phase === 'initial')
    return { terms: [], message: null, isClearVisible: false };
  if (phase === 'failed')
    return {
      terms: [],
      message: '최근 검색어를 불러오지 못했어요.',
      isClearVisible: true,
    };
  return {
    terms,
    message: terms.length === 0 ? '최근 검색어가 없어요.' : null,
    isClearVisible: terms.length !== 0,
  };
}
