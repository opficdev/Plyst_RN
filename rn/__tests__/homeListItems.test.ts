import type { ClipRecord } from 'plyst-bridge';
import { makeHomeListItems } from '../src/screens/homeListItems';
const clip: ClipRecord = {
  id: 'text',
  text: '원문',
  characterCount: 2,
  textPrefix: '원문',
  image: null,
  name: null,
  memo: null,
  isPinned: false,
  isWebLink: true,
  createdAt: 1000,
  lastUsedAt: null,
};

test('고정 행과 구간 제목 및 카드 순서를 유지한다', () => {
  const pinned = { ...clip, id: 'pinned', isPinned: true };
  const older = { ...clip, id: 'older' };
  const content = {
    pinnedClips: [pinned],
    sections: [
      { kind: 'recent' as const, clips: [clip] },
      { kind: 'earlier' as const, clips: [older] },
    ],
    isEmpty: false,
  };
  expect(makeHomeListItems(content)).toEqual([
    { kind: 'pinned', key: 'pinned', clips: [pinned] },
    {
      kind: 'section',
      key: 'section:recent',
      section: 'recent',
      hasPreviousSection: false,
    },
    { kind: 'card', key: 'clip:text', clip },
    {
      kind: 'section',
      key: 'section:earlier',
      section: 'earlier',
      hasPreviousSection: true,
    },
    { kind: 'card', key: 'clip:older', clip: older },
  ]);
  expect(content.sections[0].clips).toEqual([clip]);
});

test('빈 목록과 고정 행만 있는 목록을 구분한다', () => {
  expect(
    makeHomeListItems({ pinnedClips: [], sections: [], isEmpty: true }),
  ).toEqual([]);
  expect(
    makeHomeListItems({ pinnedClips: [clip], sections: [], isEmpty: false }),
  ).toEqual([{ kind: 'pinned', key: 'pinned', clips: [clip] }]);
});

test('고정 행이 없으면 첫 구간에 추가 간격을 두지 않는다', () => {
  expect(
    makeHomeListItems({
      pinnedClips: [],
      sections: [{ kind: 'today', clips: [clip] }],
      isEmpty: false,
    })[0],
  ).toEqual({
    kind: 'section',
    key: 'section:today',
    section: 'today',
    hasPreviousSection: false,
  });
});
