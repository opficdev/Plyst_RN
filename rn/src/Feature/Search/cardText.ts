import type { ClipRecord } from '../../Model/clipRecord';
import type { SearchIndex } from './match';

export function searchCardText(clip: ClipRecord, query: string, index: SearchIndex) {
  const { nameRanges: nameHighlights, bodyRanges: ranges, excerptStart: start } = index.cardText(clip, query);
  const original = clip.text ?? '';
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
