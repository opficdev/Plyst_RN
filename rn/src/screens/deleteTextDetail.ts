import { deleteClip } from 'plyst-bridge';

export async function deleteTextDetail(
  clipID: string,
): Promise<'deleted' | 'failed'> {
  try {
    await deleteClip(clipID);
    return 'deleted';
  } catch {
    return 'failed';
  }
}
