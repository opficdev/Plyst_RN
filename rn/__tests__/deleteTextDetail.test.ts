import { deleteClip } from 'plyst-bridge';
import { deleteTextDetail } from '../src/screens/deleteTextDetail';

jest.mock('plyst-bridge', () => ({ deleteClip: jest.fn() }));
const deleteClipMock = jest.mocked(deleteClip);

beforeEach(() => jest.resetAllMocks());

test('삭제에 성공하면 deleted이다', async () => {
  deleteClipMock.mockResolvedValue(undefined);
  await expect(deleteTextDetail('clip-id')).resolves.toBe('deleted');
  expect(deleteClipMock).toHaveBeenCalledWith('clip-id');
  expect(deleteClipMock).toHaveBeenCalledTimes(1);
});

test('브리지 오류가 발생하면 failed이다', async () => {
  deleteClipMock.mockRejectedValue(
    Object.assign(new Error('삭제 실패'), { code: 'E_DELETE_FAILED' }),
  );
  await expect(deleteTextDetail('clip-id')).resolves.toBe('failed');
});
