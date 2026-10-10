import { getClips } from 'plyst-bridge';
import type { ClipRecord } from 'plyst-bridge';
import { loadHomeClips } from '../src/screens/loadHomeClips';

jest.mock('plyst-bridge', () => ({ getClips: jest.fn() }));
const getClipsMock = jest.mocked(getClips);
const clip: ClipRecord = {
  id: 'clip-id',
  text: '원문',
  characterCount: 2,
  textPrefix: '원문',
  isWebLink: false,
  image: null,
  name: null,
  memo: null,
  isPinned: false,
  createdAt: 1234500,
  lastUsedAt: null,
};

beforeEach(() => jest.resetAllMocks());

test('전체 목록을 받은 순서 그대로 반환한다', async () => {
  const clips = [clip, { ...clip, id: 'second', createdAt: 1 }];
  getClipsMock.mockResolvedValue(clips);
  await expect(loadHomeClips()).resolves.toEqual({ status: 'loaded', clips });
  expect(getClipsMock).toHaveBeenCalledWith();
  expect(getClipsMock).toHaveBeenCalledTimes(1);
});

test('빈 목록도 조회 성공이다', async () => {
  getClipsMock.mockResolvedValue([]);
  await expect(loadHomeClips()).resolves.toEqual({
    status: 'loaded',
    clips: [],
  });
});

test('브리지 오류가 발생하면 failed이다', async () => {
  getClipsMock.mockRejectedValue(
    Object.assign(new Error('읽기 실패'), { code: 'E_READ_FAILED' }),
  );
  await expect(loadHomeClips()).resolves.toEqual({ status: 'failed' });
});
