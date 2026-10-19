import type { ClipRecord } from '../../../src/Model/clipRecord';
import { createScreenStore } from '../../../src/Shared/State/screenStore';
import {
  searchActions as actions,
  searchSlice,
} from '../../../src/Feature/Search/state';
import { startClipThumbnailListener } from '../../../src/Feature/ClipGrid/thumbnailListener';
import { loadClipThumbnail } from '../../../src/Service/Clip/loadThumbnail';
import type { ClipThumbnailResult } from '../../../src/Service/Clip/loadThumbnail';

jest.mock('plyst-bridge', () => ({}));
jest.mock('../../../src/Service/Clip/loadThumbnail');
const settle = () => new Promise<void>((resolve) => setImmediate(resolve));
function deferred() {
  let resolve!: (value: ClipThumbnailResult) => void;
  const promise = new Promise<ClipThumbnailResult>((complete) => {
    resolve = complete;
  });
  return { promise, resolve };
}
const clip: ClipRecord = {
  id: 'a',
  text: null,
  textPrefix: null,
  characterCount: 0,
  isWebLink: false,
  image: {
    contentType: 'public.png',
    pixelWidth: 2,
    pixelHeight: 3,
    byteCount: 100,
  },
  name: null,
  memo: null,
  pinnedAt: null,
  createdAt: 1,
  lastUsedAt: null,
};
function setup() {
  const pending: ReturnType<typeof deferred>[] = [];
  jest.mocked(loadClipThumbnail).mockImplementation(() => {
    const request = deferred();
    pending.push(request);
    return request.promise;
  });
  const screen = createScreenStore({
    slice: searchSlice,
    start: (listen, dispatch) =>
      startClipThumbnailListener(listen, dispatch, actions),
  });
  screen.start();
  screen.store.dispatch(
    actions.clipsLoaded({
      clips: ['a', 'b', 'c'].map((id) => ({ ...clip, id })),
      now: 1,
    }),
  );
  return { screen, pending };
}
beforeEach(() => jest.resetAllMocks());

test('listener 연결 뒤에도 요청 중복과 동시 실행 제한을 유지한다', async () => {
  const { screen, pending } = setup();
  for (const id of ['a', 'a', 'b', 'c'])
    screen.store.dispatch(actions.thumbnailRequested({ id, pixels: 200 }));
  expect(loadClipThumbnail).toHaveBeenCalledTimes(2);
  screen.store.dispatch(
    actions.thumbnailCancelRequested({ id: 'a', pixels: 200 }),
  );
  expect(loadClipThumbnail).toHaveBeenCalledTimes(2);
  pending[0].resolve({ status: 'loaded', uri: 'file://a' });
  await settle();
  expect(loadClipThumbnail).toHaveBeenCalledTimes(3);
  expect(screen.store.getState().thumbnails['a:200']).toBeUndefined();
  screen.dispose();
});

test('실행 중 취소 후 재진입하면 기존 요청을 복구한다', async () => {
  const { screen, pending } = setup();
  screen.store.dispatch(actions.thumbnailRequested({ id: 'a', pixels: 200 }));
  screen.store.dispatch(
    actions.thumbnailCancelRequested({ id: 'a', pixels: 200 }),
  );
  screen.store.dispatch(actions.thumbnailRequested({ id: 'a', pixels: 200 }));
  pending[0].resolve({ status: 'loaded', uri: 'file://a' });
  await settle();
  expect(loadClipThumbnail).toHaveBeenCalledTimes(1);
  expect(screen.store.getState().thumbnails['a:200']).toBe('file://a');
  screen.dispose();
});

test('missing은 실패로 남기지 않고 종료된 요청은 새 화면을 변경하지 않는다', async () => {
  const { screen, pending } = setup();
  screen.store.dispatch(actions.thumbnailRequested({ id: 'a', pixels: 200 }));
  pending[0].resolve({ status: 'missing' });
  await settle();
  expect(screen.store.getState().loadingThumbnails).toEqual({});
  expect(screen.store.getState().failedThumbnails).toEqual({});
  screen.store.dispatch(actions.thumbnailRequested({ id: 'b', pixels: 200 }));
  screen.dispose();
  screen.start();
  pending[1].resolve({ status: 'failed' });
  await settle();
  expect(screen.store.getState().failedThumbnails).toEqual({});
  screen.dispose();
});
