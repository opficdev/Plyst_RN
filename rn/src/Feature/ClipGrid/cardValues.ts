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

export function clipThumbnailPixels(
  columnWidth: number,
  scale: number,
  isPinned = false,
) {
  return Math.max(1, Math.ceil((isPinned ? 56 : columnWidth - 12) * scale));
}
