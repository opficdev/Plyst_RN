export function scrollOffsetToReveal(
  offset: number,
  viewportHeight: number,
  top: number,
  bottom: number,
): number {
  if (viewportHeight < bottom - top || top < offset) {
    return Math.max(0, top);
  }
  if (offset + viewportHeight < bottom) {
    return Math.max(0, bottom - viewportHeight);
  }
  return Math.max(0, offset);
}
