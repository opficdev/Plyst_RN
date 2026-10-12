import { removeSearchTerm } from 'plyst-bridge';
import { removeSearchHistoryTerm } from '../../../src/Service/Clip/removeSearchHistoryTerm';

jest.mock('plyst-bridge', () => ({ removeSearchTerm: jest.fn() }));
const removeSearchTermMock = jest.mocked(removeSearchTerm);

beforeEach(() => jest.resetAllMocks());

test('입력을 그대로 전달하고 삭제 후 검색 기록을 포함한 saved이다', async () => {
  const terms = ['이전 검색어'];
  removeSearchTermMock.mockResolvedValue(terms);
  await expect(removeSearchHistoryTerm(' 검색어\n')).resolves.toEqual({
    status: 'saved',
    terms,
  });
  expect(removeSearchTermMock).toHaveBeenCalledWith(' 검색어\n');
  expect(removeSearchTermMock).toHaveBeenCalledTimes(1);
});

test('브리지 오류가 발생하면 failed이다', async () => {
  removeSearchTermMock.mockRejectedValue(
    Object.assign(new Error('요청 실패'), { code: 'E_WRITE_FAILED' }),
  );
  await expect(removeSearchHistoryTerm(' 검색어\n')).resolves.toEqual({
    status: 'failed',
  });
});
