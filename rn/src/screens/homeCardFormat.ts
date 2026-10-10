export function formatHomeCardTime(date: number, now: number): string {
  const age = (now - date) / 1000;
  if (0 <= age && age < 60) return '지금';
  if (0 <= age && age < 300) return `${Math.floor(age / 60)}분 전`;
  const value = new Date(date);
  const today = new Date(now);
  const yesterday = new Date(now);
  yesterday.setDate(yesterday.getDate() - 1);
  const sameDay = (day: Date) =>
    value.getFullYear() === day.getFullYear() &&
    value.getMonth() === day.getMonth() &&
    value.getDate() === day.getDate();
  return new Intl.DateTimeFormat(
    undefined,
    sameDay(today) || sameDay(yesterday)
      ? { timeStyle: 'short' }
      : { dateStyle: 'medium', timeStyle: 'short' },
  ).format(value);
}
