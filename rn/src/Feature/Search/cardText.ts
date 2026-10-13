import type { ClipRecord } from '../../Model/clipRecord';
import { searchExcerptStart } from './content';
import type { SearchIndex } from './match';

export function searchCardText(
  clip: ClipRecord,
  query: string,
  index: SearchIndex,
) {
  const nameHighlights = index.ranges(clip.id, 'name', clip.name ?? '', query);
  const original = clip.text ?? '';
  const ranges = index.ranges(clip.id, 'body', original, query);
  const start = ranges.length
    ? searchExcerptStart(original, ranges[0].location)
    : 0;
  return {
    body: start === 0 ? original : `…${original.slice(start)}`,
    nameHighlights,
    bodyHighlights:
      start === 0
        ? ranges
        : ranges.map(({ location, length }) => ({
            location: location - start + 1,
            length,
          })),
  };
}
