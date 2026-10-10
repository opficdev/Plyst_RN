import { saveCurrentClipboard } from 'plyst-bridge';
import type { ClipboardSaveResult } from 'plyst-bridge';
import { saveHomeClipboard } from '../src/screens/saveHomeClipboard';

jest.mock('plyst-bridge', () => ({ saveCurrentClipboard: jest.fn() }));
const save = jest.mocked(saveCurrentClipboard);
beforeEach(() => jest.resetAllMocks());

test.each<[ClipboardSaveResult, string, boolean]>([
  ['saved', 'Plyst에 저장했습니다', true],
  ['empty', '현재 클립보드에 저장할 내용이 없습니다', false],
  ['unsupported', '지원하지 않는 클립보드 형식입니다', false],
  ['accessFailed', '현재 클립보드를 읽지 못했습니다', false],
  ['invalidImage', '이미지가 올바르지 않아 저장하지 못했습니다', false],
])('%s 결과를 원본 토스트로 변환한다', async (result, message, isSuccess) => {
  save.mockResolvedValue(result);
  await expect(saveHomeClipboard()).resolves.toEqual({ message, isSuccess });
  expect(save).toHaveBeenCalledTimes(1);
  expect(save).toHaveBeenCalledWith();
});

test('거부되면 저장 실패 토스트를 반환한다', async () => {
  save.mockRejectedValue(
    Object.assign(new Error('실패'), { code: 'E_SAVE_FAILED' }),
  );
  await expect(saveHomeClipboard()).resolves.toEqual({
    message: '클립을 저장하지 못했습니다',
    isSuccess: false,
  });
});
