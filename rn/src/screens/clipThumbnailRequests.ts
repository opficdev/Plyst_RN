const THUMBNAIL_CONCURRENCY = 2;

type Options = {
  load: (clipID: string, pixels: number) => Promise<string | null>;
  onStarted: (key: string) => void;
  onLoaded: (key: string, uri: string) => void;
  onFailed: (key: string) => void;
  onCancelled: (key: string) => void;
};
type ThumbnailRequest = {
  key: string;
  clipID: string;
  pixels: number;
  cancelled: boolean;
};

export function createThumbnailRequestQueue({
  load,
  onStarted,
  onLoaded,
  onFailed,
  onCancelled,
}: Options) {
  const requests = new Map<string, ThumbnailRequest>();
  const queued: ThumbnailRequest[] = [];
  let active = 0;
  let disposed = false;

  async function run(request: ThumbnailRequest) {
    let uri: string | null = null;
    let failed = false;
    try {
      uri = await load(request.clipID, request.pixels);
    } catch {
      failed = true;
    }
    active -= 1;
    requests.delete(request.key);
    if (!disposed && !request.cancelled) {
      if (failed) onFailed(request.key);
      else if (uri !== null) onLoaded(request.key, uri);
      // null이면 실패로 처리하지 않고 로딩 상태만 해제합니다.
      else onCancelled(request.key);
    }
    start();
  }

  function start() {
    while (!disposed && active < THUMBNAIL_CONCURRENCY && queued.length !== 0) {
      const request = queued.shift()!;
      active += 1;
      onStarted(request.key);
      void run(request);
    }
  }

  return {
    request(clipID: string, pixels: number) {
      const key = `${clipID}:${pixels}`;
      if (disposed) return;
      const existing = requests.get(key);
      if (existing) {
        if (existing.cancelled) {
          existing.cancelled = false;
          onStarted(key);
        }
        return;
      }
      const request = { key, clipID, pixels, cancelled: false };
      requests.set(key, request);
      queued.push(request);
      start();
    },
    cancel(clipID: string, pixels: number) {
      if (disposed) return;
      const key = `${clipID}:${pixels}`;
      const request = requests.get(key);
      if (!request || request.cancelled) return;
      request.cancelled = true;
      const index = queued.indexOf(request);
      if (0 <= index) {
        queued.splice(index, 1);
        requests.delete(key);
      }
      // 실행 중인 요청은 완료될 때까지 자리를 차지합니다. 결과만 버립니다.
      onCancelled(key);
    },
    dispose() {
      disposed = true;
      queued.length = 0;
      requests.clear();
    },
  };
}
