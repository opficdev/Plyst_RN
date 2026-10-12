import { subscribeClipChanges, subscribeSave } from 'plyst-bridge';
import type { ClipRecord } from 'plyst-bridge';
import { createImageDetailStore } from '../../../src/Feature/ImageDetail/store';
import { imageDetailActions as actions } from '../../../src/Feature/ImageDetail/actions';
import { loadImageDetail } from '../../../src/Service/Clip/loadImageDetail';
import { saveImageDetail } from '../../../src/Feature/ImageDetail/saveImageDetail';
import { copyClipDetail } from '../../../src/Service/Clip/copyClipDetail';
import { deleteClipDetail } from '../../../src/Service/Clip/deleteClipDetail';
import { showToast } from '../../../src/Shared/UI';

jest.mock('plyst-bridge', () => ({
  subscribeClipChanges: jest.fn(),
  subscribeSave: jest.fn(),
}));
jest.mock('../../../src/Shared/UI', () => ({ showToast: jest.fn() }));
jest.mock('../../../src/Service/Clip/loadImageDetail');
jest.mock('../../../src/Feature/ImageDetail/saveImageDetail');
jest.mock('../../../src/Service/Clip/copyClipDetail');
jest.mock('../../../src/Service/Clip/deleteClipDetail');
import { loadImageDetailPreview } from '../../../src/Service/Clip/loadImageDetailPreview';
import { saveImageDetailToPhotos } from '../../../src/Feature/ImageDetail/saveImageDetailToPhotos';
jest.mock('../../../src/Service/Clip/loadImageDetailPreview');
jest.mock('../../../src/Feature/ImageDetail/saveImageDetailToPhotos');

const clip = {
  id: 'clip',
  text: null,
  textPrefix: null,
  characterCount: 0,
  isWebLink: false,
  image: {
    contentType: 'public.png',
    pixelWidth: 2,
    pixelHeight: 3,
    byteCountText: '100 bytes',
  },
  name: null,
  memo: null,
  isPinned: false,
  createdAt: 1,
  lastUsedAt: null,
} satisfies ClipRecord;
const settle = () => new Promise<void>((resolve) => setImmediate(resolve));
function deferred<Value>() {
  let resolve!: (value: Value) => void;
  const promise = new Promise<Value>((complete) => {
    resolve = complete;
  });
  return { promise, resolve };
}
const remove = jest.fn();
beforeEach(() => {
  jest.resetAllMocks();
  jest
    .mocked(subscribeClipChanges)
    .mockReturnValue({ remove } as unknown as ReturnType<
      typeof subscribeClipChanges
    >);
  jest
    .mocked(subscribeSave)
    .mockReturnValue({ remove } as unknown as ReturnType<
      typeof subscribeClipChanges
    >);
  jest.mocked(loadImageDetail).mockResolvedValue({ status: 'loaded', clip });
  jest
    .mocked(loadImageDetailPreview)
    .mockResolvedValue({ status: 'loaded', uri: 'file://preview' });
});

async function mounted() {
  const screen = createImageDetailStore(clip.id);
  screen.start();
  screen.store.dispatch(actions.viewDidLoad());
  await settle();
  return screen;
}

test('변경 구독 뒤 최초 조회를 시작하고 로딩 뒤 저장을 구독한다', async () => {
  const pending = deferred<Awaited<ReturnType<typeof loadImageDetail>>>();
  jest.mocked(loadImageDetail).mockReturnValue(pending.promise);
  const screen = createImageDetailStore(clip.id);
  screen.start();
  expect(loadImageDetail).not.toHaveBeenCalled();
  screen.store.dispatch(actions.viewDidLoad());
  screen.store.dispatch(actions.viewDidLoad());
  expect(loadImageDetail).toHaveBeenCalledTimes(1);
  expect(
    jest.mocked(subscribeClipChanges).mock.invocationCallOrder[0],
  ).toBeLessThan(jest.mocked(loadImageDetail).mock.invocationCallOrder[0]);
  expect(subscribeSave).not.toHaveBeenCalled();
  pending.resolve({ status: 'loaded', clip });
  await settle();
  expect(subscribeSave).toHaveBeenCalledTimes(1);
  screen.dispose();
  expect(remove).toHaveBeenCalledTimes(2);
});

test('저장 중 재요청을 막고 실패해도 편집값을 보존한다', async () => {
  const pending = deferred<Awaited<ReturnType<typeof saveImageDetail>>>();
  jest.mocked(saveImageDetail).mockReturnValue(pending.promise);
  const screen = await mounted();
  screen.store.dispatch({ type: 'nameChanged', name: '수정' });
  screen.store.dispatch(actions.save());
  screen.store.dispatch(actions.save());
  expect(saveImageDetail).toHaveBeenCalledTimes(1);
  pending.resolve({ status: 'failed' });
  await settle();
  expect(screen.store.getState()).toMatchObject({
    draft: { name: '수정' },
    isSaving: false,
  });
  expect(showToast).toHaveBeenCalledWith('저장하지 못했습니다', false);
  screen.dispose();
});

test('삭제 알림은 진행 중 조회 결과로 되돌아가지 않는다', async () => {
  const screen = await mounted();
  const pending = deferred<Awaited<ReturnType<typeof loadImageDetail>>>();
  jest.mocked(loadImageDetail).mockReturnValue(pending.promise);
  const change = jest.mocked(subscribeClipChanges).mock.calls[0][0];
  change({ id: clip.id, kind: 'updated' });
  change({ id: clip.id, kind: 'deleted' });
  pending.resolve({ status: 'loaded', clip });
  await settle();
  expect(screen.store.getState()).toMatchObject({ isRemoved: true });
  screen.dispose();
});

test('종료된 저장 결과는 토스트만 표시하고 재시작한 상태를 바꾸지 않는다', async () => {
  const pending = deferred<Awaited<ReturnType<typeof saveImageDetail>>>();
  jest.mocked(saveImageDetail).mockReturnValue(pending.promise);
  const screen = await mounted();
  screen.store.dispatch({ type: 'nameChanged', name: '수정' });
  screen.store.dispatch(actions.save());
  screen.dispose();
  screen.start();
  pending.resolve({ status: 'saved', clip: { ...clip, name: '수정' } });
  await settle();
  expect(screen.store.getState()).toBeNull();
  expect(showToast).toHaveBeenCalledWith('저장했습니다', true);
  screen.dispose();
});

test('조회 실패는 최초 화면만 닫고 기존 편집 상태는 보존한다', async () => {
  const screen = await mounted();
  screen.store.dispatch({ type: 'nameChanged', name: '편집 중' });
  jest.mocked(loadImageDetail).mockResolvedValue({ status: 'failed' });
  jest
    .mocked(subscribeClipChanges)
    .mock.calls[0][0]({ id: clip.id, kind: 'updated' });
  await settle();
  expect(screen.store.getState()).toMatchObject({ draft: { name: '편집 중' } });
  screen.dispose();
  screen.start();
  screen.store.dispatch(actions.viewDidLoad());
  await settle();
  expect(screen.store.getState()).toBe('closed');
  screen.dispose();
});

test('화면 종료 뒤에도 이미 요청한 복사와 삭제 실패를 알린다', async () => {
  const copy = deferred<Awaited<ReturnType<typeof copyClipDetail>>>();
  const deletion = deferred<Awaited<ReturnType<typeof deleteClipDetail>>>();
  jest.mocked(copyClipDetail).mockReturnValue(copy.promise);
  jest.mocked(deleteClipDetail).mockReturnValue(deletion.promise);
  const screen = await mounted();
  screen.store.dispatch(actions.copy());
  screen.store.dispatch(actions.delete());
  screen.store.dispatch(actions.delete());
  expect(deleteClipDetail).toHaveBeenCalledTimes(1);
  screen.dispose();
  copy.resolve('copied');
  deletion.resolve('failed');
  await settle();
  expect(showToast).toHaveBeenCalledWith('클립보드에 복사했습니다', true);
  expect(showToast).toHaveBeenCalledWith('삭제하지 못했습니다', false);
});

test('갱신은 미리보기를 다시 요청하지 않고 사진 저장 재요청도 막는다', async () => {
  const screen = await mounted();
  jest
    .mocked(subscribeClipChanges)
    .mock.calls[0][0]({ id: clip.id, kind: 'updated' });
  await settle();
  expect(loadImageDetailPreview).toHaveBeenCalledTimes(1);
  const pending =
    deferred<Awaited<ReturnType<typeof saveImageDetailToPhotos>>>();
  jest.mocked(saveImageDetailToPhotos).mockReturnValue(pending.promise);
  screen.store.dispatch(actions.saveToPhotos());
  screen.store.dispatch(actions.saveToPhotos());
  expect(saveImageDetailToPhotos).toHaveBeenCalledTimes(1);
  screen.dispose();
  pending.resolve({
    status: 'finished',
    message: '저장 완료',
    isSuccess: true,
  });
  await settle();
  expect(showToast).toHaveBeenCalledWith('저장 완료', true);
});
