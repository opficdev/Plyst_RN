import { saveCurrentClipboard } from 'plyst-bridge';
import type { ClipboardSaveResult } from 'plyst-bridge';

export async function saveClipboard(): Promise<ClipboardSaveResult | 'failed'> {
  try {
    return await saveCurrentClipboard();
  } catch {
    return 'failed';
  }
}
