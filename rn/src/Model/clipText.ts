import { countGraphemes, splitGraphemes } from 'unicode-segmenter/grapheme';

const mark = /\p{M}/u;

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

export function clipCharacterCount(text: string | null) {
  return text === null ? 0 : countGraphemes(text);
}

export function clipTextPrefix(text: string | null) {
  if (text === null) return null;
  let prefix = '';
  let count = 0;
  for (const grapheme of splitGraphemes(text)) {
    if (60 <= count) break;
    prefix += grapheme;
    count += 1;
  }
  return prefix;
}
