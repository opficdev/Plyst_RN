export function formatByteCount(byteCount: number) {
  if (byteCount === 0) return '0KB';
  if (byteCount < 1000) return `${byteCount}바이트`;
  const units = [
    { label: 'KB', divisor: 1000, digits: 0 },
    { label: 'MB', divisor: 1_000_000, digits: 1 },
    { label: 'GB', divisor: 1_000_000_000, digits: 2 },
    { label: 'TB', divisor: 1_000_000_000_000, digits: 2 },
    { label: 'PB', divisor: 1_000_000_000_000_000, digits: 2 },
  ] as const;
  let index = 0;
  while (index < units.length - 1) {
    const unit = units[index];
    const threshold = (1000 - 0.5 / 10 ** unit.digits) * unit.divisor;
    if (byteCount < threshold) break;
    index += 1;
  }
  const unit = units[index];
  return `${formatDecimal(byteCount / unit.divisor, unit.digits)}${unit.label}`;
}

function formatDecimal(value: number, digits: number) {
  const factor = 10 ** digits;
  const rounded = Math.round((value + Number.EPSILON) * factor) / factor;
  return `${rounded}`;
}
