import { copyClip } from 'plyst-bridge';

export async function copyTextDetail(
  clipID: string,
): Promise<'copied' | 'failed'> {
  try {
    const result = await copyClip(clipID);
    return result === 'copied' || result === 'copiedWithoutLastUsedAt'
      ? 'copied'
      : 'failed';
  } catch {
    return 'failed';
  }
}
