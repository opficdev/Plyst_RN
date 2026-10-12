import { getSearchHistory } from 'plyst-bridge';
import { loadSearchHistory } from '../../../src/Service/Clip/loadSearchHistory';

jest.mock('plyst-bridge', () => ({ getSearchHistory: jest.fn() }));
const getSearchHistoryMock = jest.mocked(getSearchHistory);

beforeEach(() => jest.resetAllMocks());

test('불러온 검색 기록을 포함한 loaded이다', async () => {
  const terms = ['검색어', '이전 검색어'];
  getSearchHistoryMock.mockResolvedValue(terms);
  await expect(loadSearchHistory()).resolves.toEqual({
    status: 'loaded',
    terms,
  });
  expect(getSearchHistoryMock).toHaveBeenCalledWith();
  expect(getSearchHistoryMock).toHaveBeenCalledTimes(1);
});

test('브리지 오류가 발생하면 failed이다', async () => {
  getSearchHistoryMock.mockRejectedValue(
    Object.assign(new Error('요청 실패'), { code: 'E_READ_FAILED' }),
  );
  await expect(loadSearchHistory()).resolves.toEqual({ status: 'failed' });
});
