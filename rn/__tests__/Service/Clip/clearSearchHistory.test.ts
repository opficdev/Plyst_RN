import { removeAllSearchTerms } from 'plyst-bridge';
import { clearSearchHistory } from '../../../src/Service/Clip/clearSearchHistory';

jest.mock('plyst-bridge', () => ({ removeAllSearchTerms: jest.fn() }));
const removeAllSearchTermsMock = jest.mocked(removeAllSearchTerms);

beforeEach(() => jest.resetAllMocks());

test('전체 삭제에 성공하면 빈 검색 기록을 포함한 saved이다', async () => {
  removeAllSearchTermsMock.mockResolvedValue(undefined);
  await expect(clearSearchHistory()).resolves.toEqual({
    status: 'saved',
    terms: [],
  });
  expect(removeAllSearchTermsMock).toHaveBeenCalledWith();
  expect(removeAllSearchTermsMock).toHaveBeenCalledTimes(1);
});

test('브리지 오류가 발생하면 failed이다', async () => {
  removeAllSearchTermsMock.mockRejectedValue(
    Object.assign(new Error('요청 실패'), { code: 'E_WRITE_FAILED' }),
  );
  await expect(clearSearchHistory()).resolves.toEqual({ status: 'failed' });
});
