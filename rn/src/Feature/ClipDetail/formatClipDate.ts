export function formatClipDate(timestamp: number | null): string {
  if (timestamp === null) return '';
  const date = new Date(timestamp);
  const day = `${date.getFullYear()}년 ${date.getMonth() + 1}월 ${date.getDate()}일`;
  const hours = date.getHours();
  const period = hours < 12 ? '오전' : '오후';
  const minutes = String(date.getMinutes()).padStart(2, '0');
  return `${day}\n${period} ${hours % 12 || 12}:${minutes}`;
}
