import { wordJoiner } from '../hangulWordBreak';

// Android 줄 텍스트에는 hangulWordBreak가 넣은 WORD JOINER가 있어 원문 길이로 셈
// 원문에 원래 있던 WORD JOINER는 원문과 맞춰 세고 넣은 것만 건너뜀
function originalLength(text: string, lines: { text: string }[]) {
  let length = 0;
  for (const line of lines) {
    for (const unit of line.text.split('')) {
      if (unit !== wordJoiner || text[length] === wordJoiner) length += 1;
    }
  }
  return length;
}

export function labelTruncation(text: string, lines: { text: string }[], numberOfLines: number): number | null {
  if (!(numberOfLines > 0) || lines.length !== numberOfLines) return null;

  const newline = lines[lines.length - 1].text.match(/(\r\n|[\n\r\u2028\u2029])$/);
  if (!newline) return null;

  const length = originalLength(text, lines);
  return length < text.length ? length - newline[0].length : null;
}
