export type ToastItem = {
  id: number;
  message: string;
  isSuccess: boolean;
};
export type ToastSnapshot = { toast: ToastItem | null; isVisible: boolean };
export type ToastController = {
  show: (message: string, isSuccess: boolean) => void;
  dismissed: (id: number) => void;
  subscribe: (listener: () => void) => () => void;
  getSnapshot: () => ToastSnapshot;
};

const duration = 2000;

export function createToastController(): ToastController {
  let snapshot: ToastSnapshot = { toast: null, isVisible: false };
  let nextId = 0;
  let timer: ReturnType<typeof setTimeout> | undefined;
  const listeners = new Set<() => void>();

  function notify() {
    listeners.forEach((listener) => listener());
  }

  function hide(id: number) {
    if (snapshot.toast?.id !== id || !snapshot.isVisible) return;
    snapshot = { toast: snapshot.toast, isVisible: false };
    notify();
  }

  return {
    show(message, isSuccess) {
      const id = nextId++;
      snapshot = {
        toast: { id, message, isSuccess },
        isVisible: true,
      };
      clearTimeout(timer);
      timer = setTimeout(() => hide(id), duration);
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

export const controller = createToastController();

export function showToast(message: string, isSuccess: boolean) {
  controller.show(message, isSuccess);
}
