import { subscribeClipChanges } from 'plyst-bridge';
import type { ClipRecord } from '../../../src/Model/clipRecord';
import { createTextDetailStore } from '../../../src/Feature/TextDetail/store';
import { textDetailActions as actions } from '../../../src/Feature/TextDetail/actions';
import { loadTextDetail } from '../../../src/Service/Clip/loadTextDetail';
import { saveTextDetail } from '../../../src/Feature/TextDetail/save';
import { copyClipDetail } from '../../../src/Service/Clip/copyDetail';
import { deleteClipDetail } from '../../../src/Service/Clip/deleteDetail';
import { showToast } from '../../../src/Shared/UI';

jest.mock('plyst-bridge', () => ({
  subscribeClipChanges: jest.fn(),
}));
jest.mock('../../../src/Shared/UI', () => ({ showToast: jest.fn() }));
jest.mock('../../../src/Service/Clip/loadTextDetail');
jest.mock('../../../src/Feature/TextDetail/save');
jest.mock('../../../src/Service/Clip/copyDetail');
jest.mock('../../../src/Service/Clip/deleteDetail');

const clip = {
  id: 'clip',
  text: '원문',
  textPrefix: '원문',
  characterCount: 2,
  isWebLink: false,
  image: null,
  name: null,
  memo: null,
  pinnedAt: null,
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
  jest.mocked(loadTextDetail).mockResolvedValue({ status: 'loaded', clip });
});

async function mounted() {
  const screen = createTextDetailStore(clip.id);
  screen.start();
  screen.store.dispatch(actions.viewDidLoad());
  await settle();
  return screen;
}

test('변경 구독 뒤 최초 조회를 시작한다', async () => {
  const pending = deferred<Awaited<ReturnType<typeof loadTextDetail>>>();
  jest.mocked(loadTextDetail).mockReturnValue(pending.promise);
  const screen = createTextDetailStore(clip.id);
  screen.start();
  expect(loadTextDetail).not.toHaveBeenCalled();
  screen.store.dispatch(actions.viewDidLoad());
  screen.store.dispatch(actions.viewDidLoad());
  expect(loadTextDetail).toHaveBeenCalledTimes(1);
  expect(
    jest.mocked(subscribeClipChanges).mock.invocationCallOrder[0],
  ).toBeLessThan(jest.mocked(loadTextDetail).mock.invocationCallOrder[0]);
  pending.resolve({ status: 'loaded', clip });
  await settle();
  screen.dispose();
  expect(remove).toHaveBeenCalledTimes(1);
});

test('저장 중 재요청을 막고 실패해도 편집값을 보존한다', async () => {
  const pending = deferred<Awaited<ReturnType<typeof saveTextDetail>>>();
  jest.mocked(saveTextDetail).mockReturnValue(pending.promise);
  const screen = await mounted();
  screen.store.dispatch({ type: 'nameChanged', name: '수정' });
  screen.store.dispatch(actions.save());
  screen.store.dispatch(actions.save());
  expect(saveTextDetail).toHaveBeenCalledTimes(1);
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
  const pending = deferred<Awaited<ReturnType<typeof loadTextDetail>>>();
  jest.mocked(loadTextDetail).mockReturnValue(pending.promise);
  const change = jest.mocked(subscribeClipChanges).mock.calls[0][0];
  change({ id: clip.id, kind: 'updated' });
  change({ id: clip.id, kind: 'deleted' });
  pending.resolve({ status: 'loaded', clip });
  await settle();
  expect(screen.store.getState()).toMatchObject({ isRemoved: true });
  screen.dispose();
});

test('종료된 저장 결과는 토스트만 표시하고 재시작한 상태를 바꾸지 않는다', async () => {
  const pending = deferred<Awaited<ReturnType<typeof saveTextDetail>>>();
  jest.mocked(saveTextDetail).mockReturnValue(pending.promise);
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
  jest.mocked(loadTextDetail).mockResolvedValue({ status: 'failed' });
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
