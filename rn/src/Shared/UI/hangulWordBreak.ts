import { Platform } from 'react-native';

// Android는 lineBreakStrategyIOS가 없고 한글을 글자마다 줄바꿈함
// iOS의 standard와 hangul-word처럼 공백에서만 줄바꿈하도록 한글과 붙은 글자 사이에 WORD JOINER를 넣음
const breaksHangulByCharacter = Platform.OS === 'android';
export const wordJoiner = '\u2060';

function isHangul(character: string) {
  const code = character.charCodeAt(0);
  return (0xac00 <= code && code <= 0xd7a3) || (0x1100 <= code && code <= 0x11ff) || (0x3130 <= code && code <= 0x318f);
}

function joins(previous: string | undefined, next: string | undefined) {
  if (previous === undefined || next === undefined) return false;
  if (/\s/.test(previous) || /\s/.test(next)) return false;
  return isHangul(previous) || isHangul(next);
}

// 강조 구간처럼 나눠 그리는 조각은 다음 조각과의 경계도 이어 붙임
export function hangulWordBreak(text: string, start = 0, end = text.length): string {
  if (!breaksHangulByCharacter) return text.slice(start, end);
  let result = '';
  for (let index = start; index < end; index += 1) {
    result += text[index];
    if (joins(text[index], text[index + 1])) result += wordJoiner;
  }
  return result;
}
