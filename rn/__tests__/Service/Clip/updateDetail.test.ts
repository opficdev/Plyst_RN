import { updateClip } from 'plyst-bridge';
import type { ClipRecord } from 'plyst-bridge';
import { updateClipDetail } from '../../../src/Service/Clip/updateDetail';

jest.mock('plyst-bridge', () => ({ updateClip: jest.fn() }));
const updateClipMock = jest.mocked(updateClip);
const clip: ClipRecord = {
  id: 'clip-id',
  text: '원문',
  characterCount: 2,
  textPrefix: '원문',
  isWebLink: false,
  image: null,
  name: '이름',
  memo: ' 메모\n',
  isPinned: true,
  createdAt: 1234500,
  lastUsedAt: null,
};

beforeEach(() => jest.resetAllMocks());

test('저장에 성공하면 반환된 클립을 포함한 saved이다', async () => {
  updateClipMock.mockResolvedValue(clip);
  await expect(
    updateClipDetail(clip.id, clip.name, clip.memo, clip.isPinned),
  ).resolves.toEqual({ status: 'saved', clip });
  expect(updateClipMock).toHaveBeenCalledWith(
    clip.id,
    clip.name,
    clip.memo,
    clip.isPinned,
  );
  expect(updateClipMock).toHaveBeenCalledTimes(1);
});

test('저장 결과가 null이면 removed이다', async () => {
  updateClipMock.mockResolvedValue(null);
  await expect(
    updateClipDetail(clip.id, clip.name, clip.memo, clip.isPinned),
  ).resolves.toEqual({ status: 'removed' });
});

test('브리지 오류가 발생하면 failed이다', async () => {
  updateClipMock.mockRejectedValue(
    Object.assign(new Error('저장 실패'), { code: 'E_WRITE_FAILED' }),
  );
  await expect(
    updateClipDetail(clip.id, clip.name, clip.memo, clip.isPinned),
  ).resolves.toEqual({ status: 'failed' });
});
