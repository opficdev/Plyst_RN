import { countGraphemes, splitGraphemes } from 'unicode-segmenter/grapheme';

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
