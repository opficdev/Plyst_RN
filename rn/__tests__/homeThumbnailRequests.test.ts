import { createThumbnailRequestQueue } from '../src/screens/homeThumbnailRequests';

function deferred() {
  let resolve!: (uri: string | null) => void;
  let reject!: (error: Error) => void;
  const promise = new Promise<string | null>((complete, fail) => {
    resolve = complete;
    reject = fail;
  });
  return { promise, resolve, reject };
}
function setup(concurrency?: number) {
  const pending: ReturnType<typeof deferred>[] = [];
  const load = jest.fn((_clipID: string, _pixels: number) => {
    const request = deferred();
    pending.push(request);
    return request.promise;
  });
  const onStarted = jest.fn();
  const onLoaded = jest.fn();
  const onFailed = jest.fn();
  const onCancelled = jest.fn();
  const queue = createThumbnailRequestQueue({
    load,
    onStarted,
    onLoaded,
    onFailed,
    onCancelled,
    concurrency,
  });
  return { queue, pending, load, onStarted, onLoaded, onFailed, onCancelled };
}

test('기본 동시 요청은 정확히 2개이며 나머지는 들어온 순서대로 시작한다', async () => {
  const { queue, pending, load, onStarted, onLoaded } = setup();
  for (const id of ['a', 'b', 'c', 'd']) queue.request(id, 200);
  expect(load.mock.calls).toEqual([
    ['a', 200],
    ['b', 200],
  ]);
  expect(onStarted.mock.calls).toEqual([['a:200'], ['b:200']]);
  pending[1].resolve('file:///b.png');
  await pending[1].promise;
  expect(load.mock.calls).toEqual([
    ['a', 200],
    ['b', 200],
    ['c', 200],
  ]);
  pending[0].resolve('file:///a.png');
  await pending[0].promise;
  expect(load.mock.calls).toEqual([
    ['a', 200],
    ['b', 200],
    ['c', 200],
    ['d', 200],
  ]);
  expect(onLoaded.mock.calls).toEqual([
    ['b:200', 'file:///b.png'],
    ['a:200', 'file:///a.png'],
  ]);
  queue.dispose();
});

test('대기 중이거나 실행 중인 같은 키 요청은 중복하지 않는다', async () => {
  const { queue, pending, load } = setup(1);
  queue.request('a', 200);
  queue.request('a', 200);
  queue.request('b', 200);
  queue.request('b', 200);
  queue.request('a', 400);
  expect(load.mock.calls).toEqual([['a', 200]]);
  pending[0].resolve(null);
  await pending[0].promise;
  expect(load.mock.calls).toEqual([
    ['a', 200],
    ['b', 200],
  ]);
  pending[1].resolve(null);
  await pending[1].promise;
  expect(load.mock.calls).toEqual([
    ['a', 200],
    ['b', 200],
    ['a', 400],
  ]);
  queue.dispose();
});

test('대기 요청을 취소하면 전송하지 않고 나머지 순서를 유지한다', async () => {
  const { queue, pending, load, onCancelled, onStarted } = setup(1);
  for (const id of ['a', 'b', 'c']) queue.request(id, 200);
  queue.cancel('b', 200);
  queue.cancel('b', 200);
  queue.cancel('missing', 200);
  expect(onCancelled.mock.calls).toEqual([['b:200']]);
  pending[0].resolve(null);
  await pending[0].promise;
  expect(load.mock.calls).toEqual([
    ['a', 200],
    ['c', 200],
  ]);
  expect(onStarted.mock.calls).toEqual([['a:200'], ['c:200']]);
  queue.dispose();
});

test.each(['resolve', 'reject'] as const)(
  '진행 중 요청 취소 후 %s 결과를 버리고 완료 뒤 다음 요청을 시작한다',
  async (finish) => {
    const { queue, pending, load, onCancelled, onLoaded, onFailed } = setup(1);
    queue.request('a', 200);
    queue.request('b', 200);
    queue.cancel('a', 200);
    queue.cancel('a', 200);
    expect(load).toHaveBeenCalledTimes(1);
    expect(onCancelled.mock.calls).toEqual([['a:200']]);
    if (finish === 'resolve') pending[0].resolve('file:///a.png');
    else pending[0].reject(new Error('실패'));
    await pending[0].promise.catch(() => {});
    expect(onLoaded).not.toHaveBeenCalled();
    expect(onFailed).not.toHaveBeenCalled();
    expect(load.mock.calls).toEqual([
      ['a', 200],
      ['b', 200],
    ]);
    queue.dispose();
  },
);

test.each(['resolve', 'reject'] as const)(
  '취소한 진행 중 요청을 다시 요청하면 기존 요청의 %s 결과를 전달한다',
  async (finish) => {
    const { queue, pending, load, onStarted, onCancelled, onLoaded, onFailed } =
      setup(1);
    queue.request('a', 200);
    queue.cancel('a', 200);
    queue.request('a', 200);
    expect(load.mock.calls).toEqual([['a', 200]]);
    expect(onStarted.mock.calls).toEqual([['a:200'], ['a:200']]);
    expect(onCancelled.mock.calls).toEqual([['a:200']]);
    if (finish === 'resolve') pending[0].resolve('file:///a.png');
    else pending[0].reject(new Error('실패'));
    await pending[0].promise.catch(() => {});
    if (finish === 'resolve') {
      expect(onLoaded.mock.calls).toEqual([['a:200', 'file:///a.png']]);
      expect(onFailed).not.toHaveBeenCalled();
    } else {
      expect(onLoaded).not.toHaveBeenCalled();
      expect(onFailed.mock.calls).toEqual([['a:200']]);
    }
    expect(load.mock.calls).toEqual([['a', 200]]);
    queue.dispose();
  },
);

test.each(['resolve', 'reject'] as const)(
  '취소한 진행 중 요청을 다시 요청한 뒤 재취소하면 %s 결과를 버린다',
  async (finish) => {
    const { queue, pending, load, onStarted, onCancelled, onLoaded, onFailed } =
      setup(1);
    queue.request('a', 200);
    queue.cancel('a', 200);
    queue.request('a', 200);
    queue.cancel('a', 200);
    expect(onStarted.mock.calls).toEqual([['a:200'], ['a:200']]);
    expect(onCancelled.mock.calls).toEqual([['a:200'], ['a:200']]);
    if (finish === 'resolve') pending[0].resolve('file:///a.png');
    else pending[0].reject(new Error('실패'));
    await pending[0].promise.catch(() => {});
    expect(onLoaded).not.toHaveBeenCalled();
    expect(onFailed).not.toHaveBeenCalled();
    expect(load.mock.calls).toEqual([['a', 200]]);
    queue.dispose();
  },
);

test('취소한 대기 요청은 새로 요청할 수 있다', async () => {
  const { queue, pending, load } = setup(1);
  queue.request('a', 200);
  queue.request('b', 200);
  queue.cancel('b', 200);
  queue.request('b', 200);
  pending[0].resolve(null);
  await pending[0].promise;
  expect(load.mock.calls).toEqual([
    ['a', 200],
    ['b', 200],
  ]);
  queue.dispose();
});

test('null은 취소를 통지해 로딩 상태를 해제하고 다음 요청을 시작한다', async () => {
  const { queue, pending, load, onLoaded, onFailed, onCancelled } = setup(1);
  queue.request('a', 200);
  queue.request('b', 200);
  pending[0].resolve(null);
  await pending[0].promise;
  expect(onLoaded).not.toHaveBeenCalled();
  expect(onFailed).not.toHaveBeenCalled();
  expect(onCancelled).toHaveBeenCalledTimes(1);
  expect(onCancelled).toHaveBeenCalledWith('a:200');
  expect(load).toHaveBeenCalledTimes(2);
  queue.dispose();
});

test('실패는 한 번 통지하며 자동 재시도하지 않는다', async () => {
  const { queue, pending, load, onFailed } = setup();
  queue.request('a', 200);
  pending[0].reject(new Error('실패'));
  await pending[0].promise.catch(() => {});
  expect(onFailed.mock.calls).toEqual([['a:200']]);
  expect(load).toHaveBeenCalledTimes(1);
  queue.request('a', 200);
  expect(load).toHaveBeenCalledTimes(2);
  queue.dispose();
});

test('완료한 키는 명시적으로 다시 요청할 수 있다', async () => {
  const { queue, pending, load } = setup();
  queue.request('a', 200);
  pending[0].resolve('file:///a.png');
  await pending[0].promise;
  queue.request('a', 200);
  expect(load).toHaveBeenCalledTimes(2);
  queue.dispose();
});

test('정리 후 성공과 실패를 버리고 대기 요청과 새 요청도 시작하지 않는다', async () => {
  const { queue, pending, load, onLoaded, onFailed, onCancelled, onStarted } =
    setup();
  for (const id of ['a', 'b', 'c']) queue.request(id, 200);
  queue.dispose();
  queue.dispose();
  queue.request('d', 200);
  queue.cancel('a', 200);
  pending[0].resolve('file:///a.png');
  pending[1].reject(new Error('실패'));
  await Promise.allSettled(pending.map((request) => request.promise));
  expect(load).toHaveBeenCalledTimes(2);
  expect(onStarted).toHaveBeenCalledTimes(2);
  expect(onLoaded).not.toHaveBeenCalled();
  expect(onFailed).not.toHaveBeenCalled();
  expect(onCancelled).not.toHaveBeenCalled();
});

test('서로 다른 큐는 요청 상태를 공유하지 않는다', () => {
  const first = setup();
  const second = setup();
  first.queue.request('a', 200);
  first.queue.dispose();
  second.queue.request('a', 200);
  expect(first.load).toHaveBeenCalledTimes(1);
  expect(second.load).toHaveBeenCalledTimes(1);
  second.queue.dispose();
});
