import type { ClipboardSaveResult } from 'plyst-bridge';
import { saveClipboard } from '../../Service/Clip/saveClipboard';

const messages: Record<ClipboardSaveResult, string> = {
  saved: 'Plyst에 저장했습니다',
  empty: '현재 클립보드에 저장할 내용이 없습니다',
  unsupported: '지원하지 않는 클립보드 형식입니다',
  accessFailed: '현재 클립보드를 읽지 못했습니다',
  invalidImage: '이미지가 올바르지 않아 저장하지 못했습니다',
};

export async function saveHomeClipboard() {
  const result = await saveClipboard();
  if (result === 'failed') {
    return { message: '클립을 저장하지 못했습니다', isSuccess: false };
  }
  return { message: messages[result], isSuccess: result === 'saved' };
}
