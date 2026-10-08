export type ToastItem = {
  id: string | number;
  message: string;
  isSuccess: boolean;
};
export type ToastSnapshot = { toast: ToastItem | null; isVisible: boolean };
export type ToastController = {
  show: (message: string, isSuccess: boolean, id?: string) => void;
  dismissed: (id: string | number) => void;
  subscribe: (listener: () => void) => () => void;
  getSnapshot: () => ToastSnapshot;
};

const duration = 2000;

export function createToastController(): ToastController {
  let snapshot: ToastSnapshot = { toast: null, isVisible: false };
  let lastId: string | number | undefined;
  let nextId = 0;
  let timer: ReturnType<typeof setTimeout> | undefined;
  const listeners = new Set<() => void>();

  function notify() {
    listeners.forEach((listener) => listener());
  }

  function hide(id: string | number) {
    if (snapshot.toast?.id !== id || !snapshot.isVisible) return;
    snapshot = { toast: snapshot.toast, isVisible: false };
    notify();
  }

  return {
    show(message, isSuccess, id) {
      const resolvedId = id ?? nextId++;
      if (resolvedId === lastId) return;
      lastId = resolvedId;
      snapshot = {
        toast: { id: resolvedId, message, isSuccess },
        isVisible: true,
      };
      clearTimeout(timer);
      timer = setTimeout(() => hide(resolvedId), duration);
      notify();
    },
    dismissed(id) {
      if (snapshot.toast?.id !== id || snapshot.isVisible) return;
      snapshot = { toast: null, isVisible: false };
      notify();
    },
    subscribe(listener) {
      listeners.add(listener);
      return () => {
        listeners.delete(listener);
      };
    },
    getSnapshot: () => snapshot,
  };
}
