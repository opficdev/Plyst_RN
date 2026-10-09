import { updateClip } from 'plyst-bridge';
import type { ClipRecord } from 'plyst-bridge';
import { saveImageDetail } from '../src/screens/saveImageDetail';
import type { Draft } from '../src/screens/imageDetailDraft';

jest.mock('plyst-bridge', () => ({ updateClip: jest.fn() }));
const updateClipMock = jest.mocked(updateClip);
const clip: ClipRecord = {
  id: 'clip-id',
  text: null,
  characterCount: 0,
  image: {
    contentType: 'public.png',
    pixelWidth: 2,
    pixelHeight: 3,
    byteCountText: '100 bytes',
  },
  name: '이름',
  memo: ' 메모\n',
  isPinned: true,
  createdAt: 1234500,
  lastUsedAt: null,
};
const draft: Draft = { name: ' 이름\n', isPinned: true };

beforeEach(() => jest.resetAllMocks());

test('정규화한 값으로 저장하고 반환된 클립을 전달한다', async () => {
  updateClipMock.mockResolvedValue(clip);
  await expect(saveImageDetail(clip.id, draft, clip.memo)).resolves.toEqual({
    status: 'saved',
    clip,
  });
  expect(updateClipMock).toHaveBeenCalledWith(clip.id, '이름', ' 메모\n', true);
  expect(updateClipMock).toHaveBeenCalledTimes(1);
});

test('저장 결과가 null이면 removed이다', async () => {
  updateClipMock.mockResolvedValue(null);
  await expect(saveImageDetail(clip.id, draft, clip.memo)).resolves.toEqual({
    status: 'removed',
  });
});

test('브리지 오류가 발생하면 failed이다', async () => {
  updateClipMock.mockRejectedValue(
    Object.assign(new Error('저장 실패'), { code: 'E_UPDATE_FAILED' }),
  );
  await expect(saveImageDetail(clip.id, draft, clip.memo)).resolves.toEqual({
    status: 'failed',
  });
});

test('공백뿐인 이름은 null로 전달하고 기존 메모는 그대로 둔다', async () => {
  const savedClip = { ...clip, name: null, memo: clip.memo, isPinned: false };
  updateClipMock.mockResolvedValue(savedClip);
  await expect(
    saveImageDetail(
      clip.id,
      {
        name: ' \t\n',
        isPinned: false,
      },
      clip.memo,
    ),
  ).resolves.toEqual({ status: 'saved', clip: savedClip });
  expect(updateClipMock).toHaveBeenCalledWith(clip.id, null, clip.memo, false);
  expect(updateClipMock).toHaveBeenCalledTimes(1);
});
