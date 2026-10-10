import type { ClipRecord } from 'plyst-bridge';
import {
  homeMenuTitle,
  homeMenuSummary,
  homePinTarget,
} from '../src/screens/homeMenu';

const clip: ClipRecord = {
  id: 'text',
  text: '원문',
  textPrefix: '원문',
  characterCount: 2,
  image: null,
  name: null,
  memo: null,
  isPinned: false,
  isWebLink: false,
  createdAt: 1000,
  lastUsedAt: null,
};

test('최신 클립이 없으면 고정 상태를 변경하지 않는다', () => {
  expect(homePinTarget(clip, undefined)).toBeNull();
});

test.each([false, true])(
  '메뉴를 열 때 고정 상태가 %s이고 최신 상태가 목표와 같으면 변경하지 않는다',
  (isPinned) => {
    const menuClip = { ...clip, isPinned };
    const latest = { ...clip, isPinned: !isPinned };
    expect(homePinTarget(menuClip, latest)).toBeNull();
  },
);

test.each([false, true])(
  '메뉴를 열 때 고정 상태가 %s이고 최신 상태가 같으면 반대 상태를 반환한다',
  (isPinned) => {
    const menuClip = { ...clip, isPinned };
    const latest = { ...clip, isPinned };
    expect(homePinTarget(menuClip, latest)).toBe(!isPinned);
  },
);

test('텍스트는 이름을 우선하고 없으면 Swift 접두어를 사용한다', () => {
  expect(homeMenuTitle(clip)).toBe('텍스트');
  expect(homeMenuSummary({ ...clip, name: '이름' })).toBe('이름');
  const prefix = '👨‍👩‍👧‍👦🇰🇷e\u0301'.repeat(20);
  expect(
    homeMenuSummary({ ...clip, text: prefix + '끝', textPrefix: prefix }),
  ).toBe(prefix);
});

test('이미지는 이름을 우선하고 없으면 원본 안내 문구를 사용한다', () => {
  const image = {
    ...clip,
    text: null,
    textPrefix: null,
    characterCount: 0,
    image: {
      byteCountText: '1 KB',
      contentType: 'public.png',
      pixelWidth: 1,
      pixelHeight: 1,
    },
  };
  expect(homeMenuTitle(image)).toBe('이미지');
  expect(homeMenuSummary({ ...image, name: '사진' })).toBe('사진');
  expect(homeMenuSummary(image)).toBe('이름 없는 이미지');
});
