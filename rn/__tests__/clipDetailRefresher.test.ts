import type { TextDetailResult } from '../src/screens/loadTextDetail';
import { createClipDetailRefresher } from '../src/screens/clipDetailRefresher';

function deferred() {
  let resolve!: (result: TextDetailResult) => void;
  const promise = new Promise<TextDetailResult>((complete) => {
    resolve = complete;
  });
  return { promise, resolve };
}

test('첫 조회만 초기 조회로 전달한다', async () => {
  const result: TextDetailResult = {
    status: 'loaded',
    clip: {
      id: 'clip-id',
      text: '원문',
      characterCount: 2,
      image: null,
      name: null,
      memo: null,
      isPinned: false,
      createdAt: 1234500,
      lastUsedAt: null,
    },
  };
  const onResult = jest.fn();
  const refresher = createClipDetailRefresher({
    load: jest.fn().mockResolvedValue(result),
    onResult,
  });

  await refresher.refresh();
  await refresher.refresh();

  expect(onResult.mock.calls).toEqual([
    [result, true],
    [result, false],
  ]);
});

test('겹친 조회에서 늦게 도착한 이전 응답은 무시한다', async () => {
  const first = deferred();
  const second = deferred();
  const onResult = jest.fn();
  const refresher = createClipDetailRefresher({
    load: jest
      .fn()
      .mockReturnValueOnce(first.promise)
      .mockReturnValueOnce(second.promise),
    onResult,
  });

  const firstRequest = refresher.refresh();
  const secondRequest = refresher.refresh();
  second.resolve({ status: 'missing' });
  await secondRequest;
  first.resolve({ status: 'failed' });
  await firstRequest;

  expect(onResult.mock.calls).toEqual([[{ status: 'missing' }, false]]);
});

test('최신 조회가 대기 중이어도 이전 응답은 무시한다', async () => {
  const first = deferred();
  const second = deferred();
  const onResult = jest.fn();
  const refresher = createClipDetailRefresher({
    load: jest
      .fn()
      .mockReturnValueOnce(first.promise)
      .mockReturnValueOnce(second.promise),
    onResult,
  });

  const firstRequest = refresher.refresh();
  const secondRequest = refresher.refresh();
  first.resolve({ status: 'missing' });
  await firstRequest;
  expect(onResult).not.toHaveBeenCalled();

  second.resolve({ status: 'failed' });
  await secondRequest;
  expect(onResult.mock.calls).toEqual([[{ status: 'failed' }, false]]);
});

test('무효화한 조회의 응답은 무시하고 다음 조회는 전달한다', async () => {
  const pending = deferred();
  const onResult = jest.fn();
  const refresher = createClipDetailRefresher({
    load: jest
      .fn()
      .mockReturnValueOnce(pending.promise)
      .mockResolvedValue({ status: 'missing' }),
    onResult,
  });

  const request = refresher.refresh();
  refresher.invalidate();
  pending.resolve({ status: 'failed' });
  await request;
  expect(onResult).not.toHaveBeenCalled();

  await refresher.refresh();
  expect(onResult.mock.calls).toEqual([[{ status: 'missing' }, false]]);
});

test('정리 후에는 대기 중 응답을 무시하고 새 조회도 시작하지 않는다', async () => {
  const pending = deferred();
  const load = jest.fn().mockReturnValue(pending.promise);
  const onResult = jest.fn();
  const refresher = createClipDetailRefresher({ load, onResult });

  const request = refresher.refresh();
  refresher.dispose();
  pending.resolve({ status: 'missing' });
  await request;
  await refresher.refresh();

  expect(onResult).not.toHaveBeenCalled();
  expect(load).toHaveBeenCalledTimes(1);
});

test('조회 실패 결과도 그대로 전달한다', async () => {
  const result: TextDetailResult = { status: 'failed' };
  const onResult = jest.fn();
  const refresher = createClipDetailRefresher({
    load: jest.fn().mockResolvedValue(result),
    onResult,
  });

  await refresher.refresh();

  expect(onResult).toHaveBeenCalledWith(result, true);
  expect(onResult).toHaveBeenCalledTimes(1);
});

test('화면과 무관한 결과 타입을 그대로 전달한다', async () => {
  const onResult = jest.fn();
  const refresher = createClipDetailRefresher<number>({
    load: async () => 42,
    onResult,
  });
  await refresher.refresh();
  expect(onResult).toHaveBeenCalledWith(42, true);
});
