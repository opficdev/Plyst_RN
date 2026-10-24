import type { ClipRecord } from '../../Model/clipRecord';
import { formatClipCardTime } from './cardFormat';

export function clipCardValues(
  clip: ClipRecord,
  now: number,
  isPinned = false,
) {
  const time = formatClipCardTime(clip.createdAt, now);
  const common = { name: clip.name };
  if (clip.image !== null) {
    const { pixelWidth, pixelHeight } = clip.image;
    return {
      ...common,
      kind: 'image' as const,
      metadata: isPinned
        ? '이미지'
        : `이미지 · ${pixelWidth}×${pixelHeight} · ${time}`,
    };
  }
  return {
    ...common,
    kind: 'text' as const,
    body: clip.text ?? '',
    isWebLink: clip.isWebLink,
    metadata: isPinned ? '텍스트' : `텍스트 · ${time}`,
  };
}

export function clipColumnWidth(width: number) {
  return Math.max(1, (width - 42) / 2);
}

// 오른쪽 safe area가 있으면 목록 틀을 카드 바깥 여백 16만큼 safe area 안으로 넓힘
// 그러면 오른쪽 열 카드가 safe area 경계에서 끝남
// 오른쪽 safe area가 없으면 0
export function clipListRightMargin(safeAreaRight: number) {
  return 0 < safeAreaRight ? safeAreaRight - 16 : 0;
}

export function clipThumbnailPixels(
  columnWidth: number,
  scale: number,
  isPinned = false,
) {
  return Math.max(1, Math.ceil((isPinned ? 56 : columnWidth - 12) * scale));
}
