import {
  subscribeClipChanges,
  subscribeClipboardSaveRequests,
} from 'plyst-bridge';
import type { ClipRecord } from '../../../src/Model/clipRecord';
import { createHomeStore } from '../../../src/Feature/Home/store';
import { homeActions as actions } from '../../../src/Feature/Home/state';
import { loadClips } from '../../../src/Service/Clip/load';
import { saveHomeClipboard } from '../../../src/Feature/Home/saveClipboard';
import { updateClipDetail } from '../../../src/Service/Clip/updateDetail';
import { showToast } from '../../../src/Shared/UI';

jest.mock('plyst-bridge', () => ({
  subscribeClipChanges: jest.fn(),
  subscribeClipboardSaveRequests: jest.fn(),
}));
jest.mock('../../../src/Shared/UI', () => ({ showToast: jest.fn() }));
jest.mock('../../../src/Service/Clip/load');
jest.mock('../../../src/Service/Clip/loadThumbnail');
jest.mock('../../../src/Service/Clip/updateDetail');
jest.mock('../../../src/Feature/Home/saveClipboard');

const settle = () => new Promise<void>((resolve) => setImmediate(resolve));
function deferred<Value>() {
  let resolve!: (value: Value) => void;
  const promise = new Promise<Value>((complete) => {
    resolve = complete;
  });
  return { promise, resolve };
}
const clip: ClipRecord = {
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
};

const remove = jest.fn();
beforeEach(() => {
  jest.resetAllMocks();
  jest
    .mocked(subscribeClipChanges)
    .mockReturnValue({ remove } as unknown as ReturnType<
      typeof subscribeClipChanges
    >);
  jest
    .mocked(subscribeClipboardSaveRequests)
    .mockReturnValue({ remove } as unknown as ReturnType<
      typeof subscribeClipChanges
    >);
  jest.mocked(loadClips).mockResolvedValue({ status: 'loaded', clips: [clip] });
  jest
    .mocked(saveHomeClipboard)
    .mockResolvedValue({ message: '저장했습니다', isSuccess: true });
});

test('보관된 저장 요청을 ready 중 전달해도 한 번 처리한다', async () => {
  jest.mocked(subscribeClipboardSaveRequests).mockImplementation((listener) => {
    listener();
    return { remove } as unknown as ReturnType<typeof subscribeClipChanges>;
  });
  const screen = createHomeStore();
  screen.start();
  screen.store.dispatch(actions.viewDidLoad());
  screen.store.dispatch(actions.viewDidLoad());
  await settle();
  expect(saveHomeClipboard).toHaveBeenCalledTimes(1);
  screen.dispose();
  expect(remove).toHaveBeenCalledTimes(2);
});

test('구독 중 이벤트와 조회 중 여러 변경을 다음 조회 하나로 합친다', async () => {
  const first = deferred<Awaited<ReturnType<typeof loadClips>>>();
  jest.mocked(loadClips).mockReturnValueOnce(first.promise);
  jest.mocked(subscribeClipChanges).mockImplementation((listener) => {
    listener({ kind: 'updated', id: clip.id });
    return { remove } as unknown as ReturnType<typeof subscribeClipChanges>;
  });
  const screen = createHomeStore();
  screen.start();
  screen.store.dispatch(actions.viewDidLoad());
  expect(loadClips).toHaveBeenCalledTimes(1);
  const change = jest.mocked(subscribeClipChanges).mock.calls[0][0];
  change({ kind: 'updated', id: clip.id });
  change({ kind: 'deleted', id: clip.id });
  first.resolve({ status: 'loaded', clips: [] });
  await settle();
  expect(loadClips).toHaveBeenCalledTimes(2);
  expect(screen.store.getState().clips).toEqual([clip]);
  screen.dispose();
});

test('이전 화면 조회는 재시작한 화면의 결과를 덮어쓰지 않는다', async () => {
  const first = deferred<Awaited<ReturnType<typeof loadClips>>>();
  jest.mocked(loadClips).mockReturnValueOnce(first.promise);
  const screen = createHomeStore();
  screen.start();
  screen.store.dispatch(actions.viewDidLoad());
  screen.dispose();
  screen.start();
  screen.store.dispatch(actions.viewDidLoad());
  await settle();
  first.resolve({ status: 'loaded', clips: [] });
  await settle();
  expect(screen.store.getState().clips).toEqual([clip]);
  screen.dispose();
});

test('저장 재진입을 막고 종료 후 결과 토스트를 유지한다', async () => {
  const pending = deferred<Awaited<ReturnType<typeof saveHomeClipboard>>>();
  jest.mocked(saveHomeClipboard).mockReturnValue(pending.promise);
  const screen = createHomeStore();
  screen.start();
  screen.store.dispatch(actions.saveCurrentClipboard());
  screen.store.dispatch(actions.saveCurrentClipboard());
  expect(saveHomeClipboard).toHaveBeenCalledTimes(1);
  screen.dispose();
  pending.resolve({ message: '저장했습니다', isSuccess: true });
  await settle();
  expect(showToast).toHaveBeenCalledWith('저장했습니다', true);
});

test('메뉴가 열린 뒤 바뀐 클립의 최신 내용으로 고정한다', async () => {
  jest.mocked(updateClipDetail).mockResolvedValue({ status: 'saved', clip });
  const screen = createHomeStore();
  screen.start();
  screen.store.dispatch(actions.menuShown(clip));
  screen.store.dispatch(
    actions.clipsLoaded({
      clips: [{ ...clip, name: '최신 이름' }],
      now: 2,
    }),
  );
  screen.store.dispatch(actions.setPinned());
  await settle();
  expect(updateClipDetail).toHaveBeenCalledWith(
    clip.id,
    '최신 이름',
    null,
    true,
  );
  screen.dispose();
});
