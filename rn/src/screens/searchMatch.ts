import type { ClipRecord } from 'plyst-bridge';
import type { ClipTextRange } from '../Shared/UI';
import { edgeWhitespace } from './clipWhitespace';

const mark = /\p{M}/u;
const simpleText = /^[ -~\n\r\t가-힣ㄱ-ㆎ]*$/u;
const fold = (text: string) => text.normalize('NFC').toUpperCase();

export function normalizeSearchQuery(raw: string): string {
  return raw.replace(edgeWhitespace, '');
}

function hangulKind(point: number) {
  if (
    (0x1100 <= point && point <= 0x115f) ||
    (0xa960 <= point && point <= 0xa97c)
  )
    return 'L';
  if (
    (0x1160 <= point && point <= 0x11a7) ||
    (0xd7b0 <= point && point <= 0xd7c6)
  )
    return 'V';
  if (
    (0x11a8 <= point && point <= 0x11ff) ||
    (0xd7cb <= point && point <= 0xd7fb)
  )
    return 'T';
  if (0xac00 <= point && point <= 0xd7a3)
    return (point - 0xac00) % 28 === 0 ? 'LV' : 'LVT';
  return '';
}

export function clusters(text: string): { segment: string; index: number }[] {
  const result: { segment: string; index: number }[] = [];
  let offset = 0;
  let previous = 0;
  let regionalCount = 0;
  for (const point of text) {
    const code = point.codePointAt(0)!;
    const regional = 0x1f1e6 <= code && code <= 0x1f1ff;
    const a = hangulKind(previous);
    const b = hangulKind(code);
    const hangul =
      (a === 'L' && ['L', 'V', 'LV', 'LVT'].includes(b)) ||
      (['LV', 'V'].includes(a) && ['V', 'T'].includes(b)) ||
      (['LVT', 'T'].includes(a) && b === 'T');
    const extend =
      mark.test(point) ||
      code === 0x200d ||
      previous === 0x200d ||
      (0xfe00 <= code && code <= 0xfe0f) ||
      (0xe0100 <= code && code <= 0xe01ef) ||
      (0x1f3fb <= code && code <= 0x1f3ff) ||
      hangul ||
      (regional && regionalCount % 2 === 1) ||
      (previous === 13 && code === 10);
    if (result.length !== 0 && extend)
      result[result.length - 1].segment += point;
    else result.push({ segment: point, index: offset });
    regionalCount = regional ? regionalCount + 1 : 0;
    previous = code;
    offset += point.length;
  }
  return result;
}

type ClusterMap = {
  starts: Int32Array;
  ends: Int32Array;
  boundaries: Uint8Array;
};
type SearchText = {
  original: string;
  folded: string;
  isSimple: boolean;
  map?: ClusterMap;
  query?: string;
  ranges?: ClipTextRange[];
};

function prepare(text: string): SearchText {
  const isSimple = simpleText.test(text);
  return {
    original: text,
    folded: isSimple
      ? text.toUpperCase()
      : clusters(text)
          .map(({ segment }) => fold(segment))
          .join(''),
    isSimple,
  };
}

function buildMap(value: SearchText): ClusterMap {
  if (value.map) return value.map;
  const starts = new Int32Array(value.folded.length);
  const ends = new Int32Array(value.folded.length);
  const boundaries = new Uint8Array(value.folded.length + 1);
  let offset = 0;
  for (const { segment, index } of clusters(value.original)) {
    const length = fold(segment).length;
    boundaries[offset] = 1;
    starts.fill(index, offset, offset + length);
    ends.fill(index + segment.length, offset, offset + length);
    offset += length;
    boundaries[offset] = 1;
  }
  value.map = { starts, ends, boundaries };
  return value.map;
}

function firstRange(
  value: SearchText,
  query: string,
  cursor: number,
): { range: ClipTextRange; next: number } | null {
  while (cursor < value.folded.length) {
    const start = value.folded.indexOf(query, cursor);
    if (start < 0) return null;
    const end = start + query.length;
    if (value.isSimple)
      return { range: { location: start, length: query.length }, next: end };
    const map = buildMap(value);
    if (map.boundaries[start] && map.boundaries[end]) {
      const location = map.starts[start];
      const originalEnd = map.ends[end - 1];
      cursor = end;
      while (cursor < value.folded.length && map.starts[cursor] < originalEnd)
        cursor += 1;
      return {
        range: { location, length: originalEnd - location },
        next: cursor,
      };
    }
    cursor = start + 1;
  }
  return null;
}

function textRanges(value: SearchText, rawQuery: string): ClipTextRange[] {
  const query = fold(normalizeSearchQuery(rawQuery));
  if (!query) return [];
  if (value.query === query && value.ranges) return value.ranges;
  const ranges: ClipTextRange[] = [];
  let cursor = 0;
  while (cursor < value.folded.length) {
    const found = firstRange(value, query, cursor);
    if (!found) break;
    ranges.push(found.range);
    cursor = found.next;
  }
  value.query = query;
  value.ranges = ranges;
  return ranges;
}

export function searchRanges(text: string, rawQuery: string): ClipTextRange[] {
  return textRanges(prepare(text), rawQuery);
}

export function createSearchIndex() {
  const entries = new Map<string, Map<string, SearchText>>();
  let timer: ReturnType<typeof setTimeout> | undefined;
  function cancelPrebuild() {
    if (timer !== undefined) clearTimeout(timer);
    timer = undefined;
  }
  function entry(id: string, field: string, text: string) {
    let fields = entries.get(id);
    if (!fields) {
      fields = new Map();
      entries.set(id, fields);
    }
    let value = fields.get(field);
    if (!value || value.original !== text) {
      value = prepare(text);
      fields.set(field, value);
    }
    return value;
  }
  function retain(clips: ClipRecord[]) {
    cancelPrebuild();
    const valid = new Set(clips.map((clip) => clip.id));
    for (const id of entries.keys()) if (!valid.has(id)) entries.delete(id);
    for (const clip of clips) {
      const fields = entries.get(clip.id);
      if (!fields) continue;
      for (const [field, text] of [
        ['name', clip.name ?? ''],
        ['body', clip.text ?? ''],
      ]) {
        if (fields.get(field)?.original !== text) fields.delete(field);
      }
    }
  }
  function prebuild(clips: ClipRecord[]) {
    retain(clips);
    let cursor = 0;
    function work() {
      const start = performance.now();
      while (cursor < clips.length) {
        const clip = clips[cursor++];
        for (const [field, text] of [
          ['name', clip.name ?? ''],
          ['body', clip.text ?? ''],
        ]) {
          const value = entry(clip.id, field, text);
          if (!value.isSimple) buildMap(value);
        }
        if (8 <= performance.now() - start) break;
      }
      timer = cursor < clips.length ? setTimeout(work, 0) : undefined;
    }
    timer = setTimeout(work, 0);
    return cancelPrebuild;
  }
  return {
    matches(id: string, field: string, text: string, rawQuery: string) {
      const query = fold(normalizeSearchQuery(rawQuery));
      return !!query && firstRange(entry(id, field, text), query, 0) !== null;
    },
    ranges(id: string, field: string, text: string, rawQuery: string) {
      return textRanges(entry(id, field, text), rawQuery);
    },
    retain,
    prebuild,
    cancelPrebuild,
    dispose() {
      cancelPrebuild();
      entries.clear();
    },
  };
}

export type SearchIndex = ReturnType<typeof createSearchIndex>;
