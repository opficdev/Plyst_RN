import { saveCurrentClipboard } from 'plyst-bridge';
import { saveClipboard } from '../../../src/Service/Clip/saveClipboard';

jest.mock('plyst-bridge', () => ({ saveCurrentClipboard: jest.fn() }));
const saveCurrentClipboardMock = jest.mocked(saveCurrentClipboard);

beforeEach(() => jest.resetAllMocks());

test.each([
  'saved',
  'empty',
  'unsupported',
  'accessFailed',
  'invalidImage',
] as const)('저장 결과가 %s이면 반환값도 같은 값이다', async (result) => {
  saveCurrentClipboardMock.mockResolvedValue(result);
  await expect(saveClipboard()).resolves.toBe(result);
  expect(saveCurrentClipboardMock).toHaveBeenCalledWith();
  expect(saveCurrentClipboardMock).toHaveBeenCalledTimes(1);
});

test('브리지 오류가 발생하면 failed이다', async () => {
  saveCurrentClipboardMock.mockRejectedValue(
    Object.assign(new Error('저장 실패'), { code: 'E_SAVE_FAILED' }),
  );
  await expect(saveClipboard()).resolves.toBe('failed');
});
