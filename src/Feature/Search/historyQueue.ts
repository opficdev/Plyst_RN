export function createSearchHistoryQueue() {
  let disposed = false;
  let tail = Promise.resolve();
  return {
    enqueue(operation: () => Promise<void>): Promise<void> {
      const next = tail.then(async () => {
        if (!disposed) await operation();
      });
      tail = next.catch(() => {});
      return next;
    },
    dispose() {
      disposed = true;
    },
  };
}
