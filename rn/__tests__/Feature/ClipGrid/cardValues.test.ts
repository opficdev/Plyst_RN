import type { ClipRecord } from '../../../src/Model/clipRecord';
import {
  clipCardValues,
  clipColumnWidth,
  clipListRightMargin,
  clipThumbnailPixels,
} from '../../../src/Feature/ClipGrid/cardValues';
const clip: ClipRecord = {
  id: 'text',
  text: '원문',
  characterCount: 2,
  textPrefix: '원문',
  image: null,
  name: null,
  memo: null,
  pinnedAt: null,
  isWebLink: true,
  createdAt: 1000,
  lastUsedAt: null,
};

test('텍스트 원문과 이름 및 브릿지 링크 판정을 그대로 전달한다', () => {
  expect(clipCardValues(clip, 2000)).toEqual({
    kind: 'text',
    name: null,
    body: '원문',
    isWebLink: true,
    metadata: '텍스트 · 지금',
  });
  expect(
    clipCardValues(
      {
        ...clip,
        name: '이름',
        text: 'https://example.com',
        textPrefix: 'https://example.com',
        isWebLink: false,
      },
      61000,
      true,
    ),
  ).toEqual({
    kind: 'text',
    name: '이름',
    body: 'https://example.com',
    isWebLink: false,
    metadata: '텍스트',
  });
});

test('격자 이미지에만 해상도를 표시한다', () => {
  const image = {
    ...clip,
    text: null,
    textPrefix: null,
    image: {
      pixelWidth: 1920,
      pixelHeight: 1080,
      byteCount: 1_000_000,
      contentType: 'public.png',
    },
  };
  expect(clipCardValues(image, 2000)).toEqual({
    kind: 'image',
    name: null,
    metadata: '이미지 · 1920×1080 · 지금',
  });
  expect(clipCardValues(image, 2000, true)).toEqual({
    kind: 'image',
    name: null,
    metadata: '이미지',
  });
});

test.each([320, 375, 393, 430])(
  '%i 너비에서 두 열과 양쪽 여백 및 간격의 합이 목록 너비다',
  (width) => {
    expect(clipColumnWidth(width) * 2 + 32 + 10).toBe(width);
  },
);

test('썸네일 픽셀은 올림하며 최소 1이고 고정 카드는 열 너비와 무관하다', () => {
  expect(clipThumbnailPixels(clipColumnWidth(393), 3)).toBe(491);
  expect(clipThumbnailPixels(100, 2.75, true)).toBe(154);
  expect(clipThumbnailPixels(200, 2.76, true)).toBe(155);
  expect(clipColumnWidth(0)).toBe(1);
  expect(clipThumbnailPixels(1, 3)).toBe(1);
});

test('오른쪽 safe area가 있으면 목록 틀은 카드 바깥 여백만큼 safe area 안으로 들어간다', () => {
  expect(clipListRightMargin(0)).toBe(0);
  expect(clipListRightMargin(84)).toBe(68);
  // 오른쪽 열 카드의 오른쪽 끝은 목록 틀 끝에서 카드 바깥 여백 16을 뺀 곳이다.
  const width = 466 - clipListRightMargin(84);
  expect(width - 16).toBe(466 - 84);
});
