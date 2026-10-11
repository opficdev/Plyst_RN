export function labelTruncation(
  text: string,
  lines: { text: string }[],
  numberOfLines: number,
): number | null {
  if (!(numberOfLines > 0) || lines.length !== numberOfLines) return null;

  const newline = lines[lines.length - 1].text.match(
    /(\r\n|[\n\r\u2028\u2029])$/,
  );
  if (!newline) return null;

  const length = lines.reduce((sum, line) => sum + line.text.length, 0);
  return length < text.length ? length - newline[0].length : null;
}
