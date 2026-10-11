import { createSearchHistoryQueue } from '../src/screens/searchHistoryQueue';

function gate() {
  let release!: () => void;
  const promise = new Promise<void>((resolve) => {
    release = resolve;
  });
  return { promise, release };
}

test('최초 조회와 쓰기는 요청 순서대로 하나씩 실행한다', async () => {
  const queue = createSearchHistoryQueue();
  const first = gate();
  const calls: string[] = [];
  const read = queue.enqueue(async () => {
    calls.push('read');
    await first.promise;
    calls.push('loaded');
  });
  const write = queue.enqueue(async () => {
    calls.push('write');
  });
  const remove = queue.enqueue(async () => {
    calls.push('remove');
  });
  await Promise.resolve();
  expect(calls).toEqual(['read']);
  first.release();
  await Promise.all([read, write, remove]);
  expect(calls).toEqual(['read', 'loaded', 'write', 'remove']);
});

test('실패한 작업 다음의 쓰기도 진행한다', async () => {
  const queue = createSearchHistoryQueue();
  const failed = queue.enqueue(async () => {
    throw new Error('failed');
  });
  const next = jest.fn(async () => {});
  const done = queue.enqueue(next);
  await expect(failed).rejects.toThrow('failed');
  await done;
  expect(next).toHaveBeenCalledTimes(1);
});

test('해제 뒤 아직 시작하지 않은 작업은 실행하지 않는다', async () => {
  const queue = createSearchHistoryQueue();
  const first = gate();
  const running = queue.enqueue(() => first.promise);
  const waiting = jest.fn(async () => {});
  const pending = queue.enqueue(waiting);
  await Promise.resolve();
  queue.dispose();
  first.release();
  await Promise.all([running, pending]);
  await queue.enqueue(waiting);
  expect(waiting).not.toHaveBeenCalled();
});

test('첫 작업이 시작하기 전에 해제해도 브릿지를 호출하지 않는다', async () => {
  const queue = createSearchHistoryQueue();
  const read = jest.fn(async () => {});
  const pending = queue.enqueue(read);
  queue.dispose();
  await pending;
  expect(read).not.toHaveBeenCalled();
});
