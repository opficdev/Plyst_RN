import { copyClip } from 'plyst-bridge';
import { copyTextDetail } from '../src/screens/copyTextDetail';

jest.mock('plyst-bridge', () => ({ copyClip: jest.fn() }));
const copyClipMock = jest.mocked(copyClip);

beforeEach(() => jest.resetAllMocks());

test.each(['copied', 'copiedWithoutLastUsedAt'] as const)(
  '복사 결과가 %s이면 copied이다',
  async (result) => {
    copyClipMock.mockResolvedValue(result);
    await expect(copyTextDetail('clip-id')).resolves.toBe('copied');
    expect(copyClipMock).toHaveBeenCalledWith('clip-id');
    expect(copyClipMock).toHaveBeenCalledTimes(1);
  },
);

test('복사 결과가 writeNotObserved이면 failed이다', async () => {
  copyClipMock.mockResolvedValue('writeNotObserved');
  await expect(copyTextDetail('clip-id')).resolves.toBe('failed');
});

test('복사 결과가 null이면 failed이다', async () => {
  copyClipMock.mockResolvedValue(null);
  await expect(copyTextDetail('clip-id')).resolves.toBe('failed');
});

test('브리지 오류가 발생하면 failed이다', async () => {
  copyClipMock.mockRejectedValue(
    Object.assign(new Error('복사 실패'), { code: 'E_COPY_FAILED' }),
  );
  await expect(copyTextDetail('clip-id')).resolves.toBe('failed');
});
