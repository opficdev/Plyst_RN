import { subscribeClipChanges } from 'plyst-bridge';
import type { ClipRecord } from '../../../src/Model/clipRecord';
import { createSearchStore } from '../../../src/Feature/Search/store';
import { searchActions as actions } from '../../../src/Feature/Search/state';
import { loadClips } from '../../../src/Service/Clip/load';
import { loadSearchHistory } from '../../../src/Service/Clip/loadSearchHistory';
import { recordSearchHistoryTerm } from '../../../src/Service/Clip/recordSearchHistoryTerm';
import { removeSearchHistoryTerm } from '../../../src/Service/Clip/removeSearchHistoryTerm';
import { clearSearchHistory } from '../../../src/Service/Clip/clearSearchHistory';
import { copyClipDetail } from '../../../src/Service/Clip/copyDetail';
import { showToast } from '../../../src/Shared/UI';

jest.mock('plyst-bridge', () => ({ subscribeClipChanges: jest.fn() }));
jest.mock('../../../src/Shared/UI', () => ({ showToast: jest.fn() }));
jest.mock('../../../src/Service/Clip/load');
jest.mock('../../../src/Service/Clip/loadThumbnail');
jest.mock('../../../src/Service/Clip/loadSearchHistory');
jest.mock('../../../src/Service/Clip/recordSearchHistoryTerm');
jest.mock('../../../src/Service/Clip/removeSearchHistoryTerm');
jest.mock('../../../src/Service/Clip/clearSearchHistory');
jest.mock('../../../src/Service/Clip/copyDetail');

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

beforeEach(() => {
  jest.resetAllMocks();
  jest
    .mocked(subscribeClipChanges)
    .mockReturnValue({ remove: jest.fn() } as unknown as ReturnType<
      typeof subscribeClipChanges
    >);
  jest.mocked(loadClips).mockResolvedValue({ status: 'loaded', clips: [clip] });
  jest
    .mocked(loadSearchHistory)
    .mockResolvedValue({ status: 'loaded', terms: [] });
  jest
    .mocked(recordSearchHistoryTerm)
    .mockResolvedValue({ status: 'saved', terms: ['검색'] });
  jest
    .mocked(removeSearchHistoryTerm)
    .mockResolvedValue({ status: 'saved', terms: [] });
  jest
    .mocked(clearSearchHistory)
    .mockResolvedValue({ status: 'saved', terms: [] });
});

test('초기 검색 기록 조회가 끝난 뒤 쓰기를 순서대로 실행한다', async () => {
  const initial = deferred<Awaited<ReturnType<typeof loadSearchHistory>>>();
  jest.mocked(loadSearchHistory).mockReturnValue(initial.promise);
  const screen = createSearchStore(jest.fn());
  screen.start();
  screen.store.dispatch(actions.viewDidLoad());
  screen.store.dispatch(actions.queryChanged('검색'));
  screen.store.dispatch(actions.submitQuery());
  screen.store.dispatch(actions.removeRecentTerm('검색'));
  screen.store.dispatch(actions.clearRecentTerms());
  await settle();
  expect(recordSearchHistoryTerm).not.toHaveBeenCalled();
  initial.resolve({ status: 'loaded', terms: ['기존'] });
  await settle();
  expect(recordSearchHistoryTerm).toHaveBeenCalledWith('검색');
  expect(
    jest.mocked(recordSearchHistoryTerm).mock.invocationCallOrder[0],
  ).toBeLessThan(
    jest.mocked(removeSearchHistoryTerm).mock.invocationCallOrder[0],
  );
  expect(
    jest.mocked(removeSearchHistoryTerm).mock.invocationCallOrder[0],
  ).toBeLessThan(jest.mocked(clearSearchHistory).mock.invocationCallOrder[0]);
  expect(screen.store.getState().searchHistory).toEqual([]);
  screen.dispose();
});

test('복사 완료 시점이 아닌 요청 시점의 검색어를 기록한다', async () => {
  const copy = deferred<Awaited<ReturnType<typeof copyClipDetail>>>();
  jest.mocked(copyClipDetail).mockReturnValue(copy.promise);
  const screen = createSearchStore(jest.fn());
  screen.start();
  screen.store.dispatch(actions.viewDidLoad());
  screen.store.dispatch(actions.queryChanged('  한글 검색  '));
  screen.store.dispatch(actions.copy(clip.id));
  screen.store.dispatch(actions.queryChanged('다음 검색'));
  copy.resolve('copied');
  await settle();
  expect(recordSearchHistoryTerm).toHaveBeenCalledWith('  한글 검색  ');
  screen.dispose();
});

test('화면 종료 뒤 복사는 토스트와 후속 검색 기록을 남기지 않는다', async () => {
  const copy = deferred<Awaited<ReturnType<typeof copyClipDetail>>>();
  jest.mocked(copyClipDetail).mockReturnValue(copy.promise);
  const screen = createSearchStore(jest.fn());
  screen.start();
  screen.store.dispatch(actions.queryChanged('검색'));
  screen.store.dispatch(actions.copy(clip.id));
  screen.dispose();
  copy.resolve('copied');
  await settle();
  expect(recordSearchHistoryTerm).not.toHaveBeenCalled();
  expect(showToast).not.toHaveBeenCalled();
});

test('종료된 큐의 대기 쓰기는 시작하지 않는다', async () => {
  const initial = deferred<Awaited<ReturnType<typeof loadSearchHistory>>>();
  jest.mocked(loadSearchHistory).mockReturnValue(initial.promise);
  const screen = createSearchStore(jest.fn());
  screen.start();
  screen.store.dispatch(actions.viewDidLoad());
  await settle();
  screen.store.dispatch(actions.clearRecentTerms());
  screen.dispose();
  initial.resolve({ status: 'loaded', terms: ['기존'] });
  await settle();
  expect(clearSearchHistory).not.toHaveBeenCalled();
  expect(screen.store.getState().searchHistory).toEqual([]);
});

test('검색 기록 실패는 사용자 요청만 알리고 복사 뒤 기록 실패는 조용히 처리한다', async () => {
  jest.mocked(recordSearchHistoryTerm).mockResolvedValue({ status: 'failed' });
  jest.mocked(copyClipDetail).mockResolvedValue('copied');
  const screen = createSearchStore(jest.fn());
  screen.start();
  screen.store.dispatch(actions.viewDidLoad());
  screen.store.dispatch(actions.queryChanged('검색'));
  screen.store.dispatch(actions.submitQuery());
  await settle();
  expect(showToast).toHaveBeenCalledWith(
    '최근 검색어를 변경하지 못했습니다',
    false,
  );
  jest.mocked(showToast).mockClear();
  screen.store.dispatch(actions.copy(clip.id));
  await settle();
  expect(showToast).toHaveBeenCalledTimes(1);
  expect(showToast).toHaveBeenCalledWith('클립보드에 복사했습니다', true);
  screen.dispose();
});
