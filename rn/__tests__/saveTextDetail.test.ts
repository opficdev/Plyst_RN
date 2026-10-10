import { updateClip } from 'plyst-bridge';
import type { ClipRecord } from 'plyst-bridge';
import { saveTextDetail } from '../src/screens/saveTextDetail';
import type { Draft } from '../src/screens/textDetailDraft';

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
const draft: Draft = { name: ' 이름\n', memo: ' 메모\n', isPinned: true };

beforeEach(() => jest.resetAllMocks());

test('정규화한 값으로 저장하고 반환된 클립을 전달한다', async () => {
  updateClipMock.mockResolvedValue(clip);
  await expect(saveTextDetail(clip.id, draft)).resolves.toEqual({
    status: 'saved',
    clip,
  });
  expect(updateClipMock).toHaveBeenCalledWith(clip.id, '이름', ' 메모\n', true);
  expect(updateClipMock).toHaveBeenCalledTimes(1);
});

test('저장 결과가 null이면 removed이다', async () => {
  updateClipMock.mockResolvedValue(null);
  await expect(saveTextDetail(clip.id, draft)).resolves.toEqual({
    status: 'removed',
  });
});

test('브리지 오류가 발생하면 failed이다', async () => {
  updateClipMock.mockRejectedValue(
    Object.assign(new Error('저장 실패'), { code: 'E_UPDATE_FAILED' }),
  );
  await expect(saveTextDetail(clip.id, draft)).resolves.toEqual({
    status: 'failed',
  });
});

test('공백뿐인 이름과 메모는 null로 전달한다', async () => {
  const savedClip = { ...clip, name: null, memo: null, isPinned: false };
  updateClipMock.mockResolvedValue(savedClip);
  await expect(
    saveTextDetail(clip.id, {
      name: ' \t\n',
      memo: '\n\u3000 ',
      isPinned: false,
    }),
  ).resolves.toEqual({ status: 'saved', clip: savedClip });
  expect(updateClipMock).toHaveBeenCalledWith(clip.id, null, null, false);
  expect(updateClipMock).toHaveBeenCalledTimes(1);
});
