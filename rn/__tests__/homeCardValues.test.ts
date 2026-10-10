import type { ClipRecord } from 'plyst-bridge';
import {
  homeCardValues,
  homeColumnWidth,
  homeThumbnailPixels,
} from '../src/screens/homeCardValues';
const clip: ClipRecord = {
  id: 'text',
  text: '원문',
  characterCount: 2,
  image: null,
  name: null,
  memo: null,
  isPinned: false,
  isWebLink: true,
  createdAt: 1000,
  lastUsedAt: null,
};

test('텍스트 원문과 이름 및 브릿지 링크 판정을 그대로 전달한다', () => {
  expect(homeCardValues(clip, 2000)).toEqual({
    kind: 'text',
    name: null,
    body: '원문',
    isWebLink: true,
    metadata: '텍스트 · 지금',
  });
  expect(
    homeCardValues(
      { ...clip, name: '이름', text: 'https://example.com', isWebLink: false },
      61000,
      true,
    ),
  ).toEqual({
    kind: 'text',
    name: '이름',
    body: 'https://example.com',
    isWebLink: false,
    metadata: '텍스트 · 1분 전',
  });
});

test('격자 이미지에만 해상도를 표시한다', () => {
  const image = {
    ...clip,
    text: null,
    image: {
      pixelWidth: 1920,
      pixelHeight: 1080,
      byteCountText: '1 MB',
      contentType: 'public.png',
    },
  };
  expect(homeCardValues(image, 2000)).toEqual({
    kind: 'image',
    name: null,
    metadata: '이미지 · 1920×1080 · 지금',
  });
  expect(homeCardValues(image, 2000, true)).toEqual({
    kind: 'image',
    name: null,
    metadata: '이미지 · 지금',
  });
});

test.each([320, 375, 393, 430])(
  '%i 너비에서 두 열과 양쪽 여백 및 간격의 합이 목록 너비다',
  (width) => {
    expect(homeColumnWidth(width) * 2 + 32 + 10).toBe(width);
  },
);

test('썸네일 픽셀은 올림하며 최소 1이고 고정 카드는 열 너비와 무관하다', () => {
  expect(homeThumbnailPixels(homeColumnWidth(393), 3)).toBe(491);
  expect(homeThumbnailPixels(100, 2.75, true)).toBe(154);
  expect(homeThumbnailPixels(200, 2.76, true)).toBe(155);
  expect(homeColumnWidth(0)).toBe(1);
  expect(homeThumbnailPixels(1, 3)).toBe(1);
});
