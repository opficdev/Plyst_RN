import {
  createContext,
  useContext,
  useState,
  useSyncExternalStore,
} from 'react';
import type { ReactNode } from 'react';
import { StyleSheet, View } from 'react-native';
import {
  SafeAreaProvider,
  useSafeAreaInsets,
} from 'react-native-safe-area-context';
import { FullWindowOverlay } from 'react-native-screens';
import { Toast } from './Toast';
import { createToastController } from './toastController';
import type { ToastController, ToastItem } from './toastController';

export type ToastProviderProps = { children: ReactNode };

const ToastContext = createContext<ToastController | null>(null);

export function ToastProvider({ children }: ToastProviderProps) {
  const [controller] = useState(() => createToastController());
  const snapshot = useSyncExternalStore(
    controller.subscribe,
    controller.getSnapshot,
  );

  return (
    <ToastContext.Provider value={controller}>
      {children}
      {snapshot.toast !== null && (
        <FullWindowOverlay>
          <SafeAreaProvider
            style={StyleSheet.absoluteFill}
            pointerEvents="none"
          >
            <ToastLayer
              toast={snapshot.toast}
              isVisible={snapshot.isVisible}
              controller={controller}
            />
          </SafeAreaProvider>
        </FullWindowOverlay>
      )}
    </ToastContext.Provider>
  );
}

export function useToast() {
  const controller = useContext(ToastContext);
  if (controller === null) {
    throw new Error('useToast는 ToastProvider 안에서 사용해야 합니다.');
  }
  return { show: controller.show };
}

type ToastLayerProps = {
  toast: ToastItem;
  isVisible: boolean;
  controller: ToastController;
};

function ToastLayer({ toast, isVisible, controller }: ToastLayerProps) {
  const insets = useSafeAreaInsets();

  return (
    <View
      pointerEvents="none"
      style={[styles.layer, { paddingTop: insets.top + 12 }]}
    >
      <Toast
        key={toast.id}
        message={toast.message}
        isSuccess={toast.isSuccess}
        isVisible={isVisible}
        onHidden={() => controller.dismissed(toast.id)}
      />
    </View>
  );
}

const styles = StyleSheet.create({
  layer: {
    ...StyleSheet.absoluteFill,
    paddingHorizontal: 20,
    alignItems: 'center',
  },
});
