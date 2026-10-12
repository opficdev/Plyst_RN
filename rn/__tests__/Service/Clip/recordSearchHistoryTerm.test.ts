import { recordSearchTerm } from 'plyst-bridge';
import { recordSearchHistoryTerm } from '../../../src/Service/Clip/recordSearchHistoryTerm';

jest.mock('plyst-bridge', () => ({ recordSearchTerm: jest.fn() }));
const recordSearchTermMock = jest.mocked(recordSearchTerm);

beforeEach(() => jest.resetAllMocks());

test('입력을 그대로 전달하고 저장된 검색 기록을 포함한 saved이다', async () => {
  const terms = ['검색어', '이전 검색어'];
  recordSearchTermMock.mockResolvedValue(terms);
  await expect(recordSearchHistoryTerm(' 검색어\n')).resolves.toEqual({
    status: 'saved',
    terms,
  });
  expect(recordSearchTermMock).toHaveBeenCalledWith(' 검색어\n');
  expect(recordSearchTermMock).toHaveBeenCalledTimes(1);
});

test('브리지 결과가 null이면 unchanged이다', async () => {
  recordSearchTermMock.mockResolvedValue(null);
  await expect(recordSearchHistoryTerm(' \n')).resolves.toEqual({
    status: 'unchanged',
  });
});

test('브리지 오류가 발생하면 failed이다', async () => {
  recordSearchTermMock.mockRejectedValue(
    Object.assign(new Error('요청 실패'), { code: 'E_WRITE_FAILED' }),
  );
  await expect(recordSearchHistoryTerm(' 검색어\n')).resolves.toEqual({
    status: 'failed',
  });
});
