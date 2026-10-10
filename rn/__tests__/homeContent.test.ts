import type { ClipRecord } from 'plyst-bridge';
import {
  homeFilters,
  homeFilterStrings,
  homeSectionKinds,
  homeSectionTitles,
  makeHomeContent,
  homeEmptyState,
} from '../src/screens/homeContent';
import type {
  HomeFilter,
  HomeLoadPhase,
  HomeEmptyState,
} from '../src/screens/homeContent';
const clip: ClipRecord = {
  id: 'clip-id',
  text: '원문',
  characterCount: 2,
  isWebLink: false,
  image: null,
  name: null,
  memo: null,
  isPinned: false,
  createdAt: 1234500,
  lastUsedAt: null,
};
const now = new Date(2026, 9, 10, 12).getTime();
const image: ClipRecord = {
  ...clip,
  id: 'image',
  text: null,
  image: {
    byteCountText: '1 KB',
    contentType: 'public.png',
    pixelWidth: 10,
    pixelHeight: 10,
  },
  createdAt: now - 1000,
};

test('필터 순서와 모든 고정 문구는 원본과 같다', () => {
  expect(homeFilters).toEqual(['all', 'text', 'image', 'pinned']);
  expect(homeFilters.map((filter) => homeFilterStrings[filter])).toEqual([
    {
      title: '전체',
      emptyTitle: '아직 저장된 내용이 없습니다',
      emptyMessage:
        '텍스트나 이미지를 복사한 뒤 현재 클립보드 저장을 눌러보세요',
    },
    {
      title: '텍스트',
      emptyTitle: '저장된 텍스트가 없습니다',
      emptyMessage: '텍스트를 복사한 뒤 현재 클립보드 저장을 눌러보세요',
    },
    {
      title: '이미지',
      emptyTitle: '저장된 이미지가 없습니다',
      emptyMessage: '이미지를 복사한 뒤 현재 클립보드 저장을 눌러보세요',
    },
    {
      title: '고정',
      emptyTitle: '고정한 항목이 없습니다',
      emptyMessage: '항목을 길게 눌러 고정할 수 있어요',
    },
  ]);
  expect(homeSectionKinds).toEqual(['recent', 'today', 'yesterday', 'earlier']);
  expect(homeSectionTitles).toEqual({
    recent: '방금',
    today: '오늘',
    yesterday: '어제',
    earlier: '이전',
  });
});

test('미래와 5분 경계 및 현지 날짜 경계를 생성 시각으로 분류한다', () => {
  const times = [
    now + 1000,
    now - 299000,
    now - 300000,
    new Date(2026, 9, 10).getTime(),
    new Date(2026, 9, 10).getTime() - 1,
    new Date(2026, 9, 9).getTime(),
    new Date(2026, 9, 9).getTime() - 1,
  ];
  const clips = times.map((createdAt, index) => ({
    ...clip,
    id: `${index}`,
    createdAt,
    lastUsedAt: now,
  }));
  expect(makeHomeContent(clips, 'all', now)).toEqual({
    pinnedClips: [],
    isEmpty: false,
    sections: [
      { kind: 'recent', clips: clips.slice(0, 2) },
      { kind: 'today', clips: clips.slice(2, 4) },
      { kind: 'yesterday', clips: clips.slice(4, 6) },
      { kind: 'earlier', clips: clips.slice(6) },
    ],
  });
});

test('자정을 지나도 5분 미만이면 방금에 속한다', () => {
  const midnight = new Date(2026, 9, 10).getTime();
  const recent = { ...clip, createdAt: midnight - 299000 };
  const yesterday = { ...clip, id: 'yesterday', createdAt: midnight - 300000 };
  expect(
    makeHomeContent([recent, yesterday], 'all', midnight).sections,
  ).toEqual([
    { kind: 'recent', clips: [recent] },
    { kind: 'yesterday', clips: [yesterday] },
  ]);
});

const pinnedText = {
  ...clip,
  id: 'pinned-text',
  isPinned: true,
  createdAt: now,
};
const pinnedImage = { ...image, id: 'pinned-image', isPinned: true };
const text = { ...clip, id: 'text', createdAt: now - 2000, isWebLink: true };
const clips = [pinnedText, pinnedImage, image, text];

test.each<[HomeFilter, ClipRecord[], ClipRecord[]]>([
  ['all', [pinnedText, pinnedImage], [image, text]],
  ['text', [], [pinnedText, text]],
  ['image', [], [pinnedImage, image]],
  ['pinned', [], [pinnedText, pinnedImage]],
])(
  '%s 필터는 입력 순서를 유지하며 전체에서만 고정 목록을 분리한다',
  (filter, pinnedClips, timeline) => {
    const before = clips.map((value) => ({ ...value }));
    expect(makeHomeContent(clips, filter, now)).toEqual({
      pinnedClips,
      sections: [{ kind: 'recent', clips: timeline }],
      isEmpty: false,
    });
    expect(clips).toEqual(before);
  },
);

test('고정 목록만 있어도 비어 있지 않다', () => {
  expect(makeHomeContent([pinnedText], 'all', now)).toEqual({
    pinnedClips: [pinnedText],
    sections: [],
    isEmpty: false,
  });
});

test.each(homeFilters)('%s 필터의 빈 결과에는 빈 섹션이 없다', (filter) => {
  expect(makeHomeContent([], filter, now)).toEqual({
    pinnedClips: [],
    sections: [],
    isEmpty: true,
  });
});

test.each<[HomeLoadPhase, boolean, boolean, HomeEmptyState]>([
  ['loading', true, true, 'none'],
  ['loading', false, true, 'none'],
  ['loading', false, false, 'none'],
  ['loaded', true, true, 'empty'],
  ['loaded', false, true, 'filtered'],
  ['loaded', false, false, 'none'],
  ['failed', true, true, 'failed'],
  ['failed', false, true, 'none'],
  ['failed', false, false, 'none'],
])(
  '%s에서 전체 목록 비어 있음 %s와 표시 내용 비어 있음 %s를 판별한다',
  (loadPhase, noClips, isEmpty, expected) => {
    expect(
      homeEmptyState({
        loadPhase,
        clips: noClips ? [] : [text],
        content: { pinnedClips: [], sections: [], isEmpty },
      }),
    ).toBe(expected);
  },
);
