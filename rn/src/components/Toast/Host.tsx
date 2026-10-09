import { useSyncExternalStore } from 'react';
import { StyleSheet, View } from 'react-native';
import {
  SafeAreaProvider,
  useSafeAreaInsets,
} from 'react-native-safe-area-context';
import { Toast } from './View';
import { controller } from './controller';
import type { ToastItem } from './controller';

export function ToastHost() {
  const snapshot = useSyncExternalStore(
    controller.subscribe,
    controller.getSnapshot,
  );

  return (
    <SafeAreaProvider
      style={[StyleSheet.absoluteFill, styles.root]}
      pointerEvents="none"
    >
      {snapshot.toast !== null && (
        <ToastLayer toast={snapshot.toast} isVisible={snapshot.isVisible} />
      )}
    </SafeAreaProvider>
  );
}

type ToastLayerProps = {
  toast: ToastItem;
  isVisible: boolean;
};

function ToastLayer({ toast, isVisible }: ToastLayerProps) {
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
  root: { backgroundColor: 'transparent' },
  layer: {
    ...StyleSheet.absoluteFill,
    paddingHorizontal: 20,
    alignItems: 'center',
  },
});
