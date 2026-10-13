import type { ClipRecord } from '../../Model/clipRecord';

export function homeMenuTitle(clip: ClipRecord) {
  return clip.image === null ? '텍스트' : '이미지';
}

export function homeMenuSummary(clip: ClipRecord) {
  return clip.name ?? clip.textPrefix ?? '이름 없는 이미지';
}

export function homePinTarget(
  menuClip: ClipRecord,
  latest: ClipRecord | undefined,
): boolean | null {
  const target = menuClip.pinnedAt === null;
  return !latest || (latest.pinnedAt !== null) === target ? null : target;
}
