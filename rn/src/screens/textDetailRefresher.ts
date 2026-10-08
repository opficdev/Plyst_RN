import type { TextDetailResult } from './loadTextDetail';

type Options = {
  load: () => Promise<TextDetailResult>;
  onResult: (result: TextDetailResult, isInitial: boolean) => void;
};

export function createTextDetailRefresher({ load, onResult }: Options) {
  let request = 0;
  let started = false;
  let disposed = false;

  return {
    async refresh() {
      if (disposed) return;
      const current = ++request;
      const isInitial = !started;
      started = true;
      const result = await load();
      if (!disposed && current === request) onResult(result, isInitial);
    },
    invalidate() {
      request += 1;
    },
    dispose() {
      disposed = true;
      request += 1;
    },
  };
}
