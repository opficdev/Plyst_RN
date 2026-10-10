import type { ClipRecord } from 'plyst-bridge';
import { formatHomeCardTime } from './homeCardFormat';

export function homeCardValues(
  clip: ClipRecord,
  now: number,
  isPinned = false,
) {
  const time = formatHomeCardTime(clip.createdAt, now);
  const common = { name: clip.name };
  if (clip.image !== null) {
    const { pixelWidth, pixelHeight } = clip.image;
    return {
      ...common,
      kind: 'image' as const,
      metadata: isPinned
        ? `이미지 · ${time}`
        : `이미지 · ${pixelWidth}×${pixelHeight} · ${time}`,
    };
  }
  return {
    ...common,
    kind: 'text' as const,
    body: clip.text ?? '',
    isWebLink: clip.isWebLink,
    metadata: `텍스트 · ${time}`,
  };
}

export function homeColumnWidth(width: number) {
  return Math.max(1, (width - 42) / 2);
}

export function homeThumbnailPixels(
  columnWidth: number,
  scale: number,
  isPinned = false,
) {
  return Math.max(1, Math.ceil((isPinned ? 56 : columnWidth - 12) * scale));
}
