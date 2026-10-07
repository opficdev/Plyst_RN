import { useEffect, useRef } from 'react';
import {
  Keyboard,
  Modal,
  Pressable,
  ScrollView,
  StyleSheet,
  Text,
  View,
} from 'react-native';
import {
  SafeAreaProvider,
  useSafeAreaInsets,
} from 'react-native-safe-area-context';
import { colors } from '../../theme';
import { ActionSheetButton } from './ActionSheetButton';
import type { ActionSheetItem } from './ActionSheetItem';

export type ActionSheetProps = {
  // 항상 마운트하고 isVisible로만 열고 닫는다. 조건부로 렌더링하면 닫힘 뒤에 실행되어야 할 handler가 사라진다.
  isVisible: boolean;
  title: string;
  message: string;
  items: ActionSheetItem[];
  onClose: () => void;
};
export function ActionSheet({
  isVisible,
  title,
  message,
  items,
  onClose,
}: ActionSheetProps) {
  const didFinish = useRef(false);
  const pendingItem = useRef<ActionSheetItem | undefined>(undefined);

  useEffect(() => {
    if (isVisible) {
      didFinish.current = false;
      pendingItem.current = undefined;
      Keyboard.dismiss();
    }
  }, [isVisible]);

  function select(item?: ActionSheetItem) {
    if (didFinish.current) return;
    didFinish.current = true;
    pendingItem.current = item;
    onClose();
  }

  function cancel() {
    select(items.filter((item) => item.role === 'cancel').pop());
  }

  function dismiss() {
    const item = pendingItem.current;
    // handler가 화면을 다시 표시할 때 새 선택 상태가 지워지지 않도록 호출 전에 대기 중인 항목을 초기화한다.
    pendingItem.current = undefined;
    item?.handler?.();
  }

  return (
    <Modal
      transparent
      animationType="fade"
      visible={isVisible}
      onDismiss={dismiss}
    >
      <SafeAreaProvider>
        <ActionSheetContent
          title={title}
          message={message}
          items={items}
          onSelect={select}
          onCancel={cancel}
        />
      </SafeAreaProvider>
    </Modal>
  );
}

type ActionSheetContentProps = {
  title: string;
  message: string;
  items: ActionSheetItem[];
  onSelect: (item: ActionSheetItem) => void;
  onCancel: () => void;
};
function ActionSheetContent({
  title,
  message,
  items,
  onSelect,
  onCancel,
}: ActionSheetContentProps) {
  const insets = useSafeAreaInsets();
  const orderedItems = [
    ...items.filter((item) => item.role !== 'cancel'),
    ...items.filter((item) => item.role === 'cancel'),
  ];

  return (
    <View
      style={[
        styles.container,
        {
          paddingLeft: insets.left + 32,
          paddingRight: insets.right + 32,
          paddingTop: insets.top + 12,
          paddingBottom: insets.bottom + 12,
        },
      ]}
    >
      <Pressable style={styles.scrim} onPress={onCancel} />
      <View style={styles.card}>
        <View style={styles.header}>
          <Text style={styles.title}>{title}</Text>
          <Text style={styles.message} numberOfLines={4}>
            {message}
          </Text>
        </View>
        <ScrollView
          style={styles.scroll}
          contentContainerStyle={styles.buttons}
          alwaysBounceVertical={false}
          showsVerticalScrollIndicator={false}
        >
          {orderedItems.map((item, index) => (
            <ActionSheetButton
              key={index}
              title={item.title}
              role={item.role}
              onPress={() => onSelect(item)}
            />
          ))}
        </ScrollView>
      </View>
    </View>
  );
}
const styles = StyleSheet.create({
  container: { flex: 1, justifyContent: 'center' },
  scrim: { ...StyleSheet.absoluteFill, backgroundColor: colors.Shadow },
  card: {
    backgroundColor: colors.Card,
    borderRadius: 32,
    borderCurve: 'continuous',
    overflow: 'hidden',
    flexShrink: 1,
  },
  header: {
    paddingTop: 28,
    paddingHorizontal: 24,
    gap: 6,
    flexShrink: 0,
  },
  title: {
    fontSize: 20,
    fontWeight: '700',
    color: colors.PrimaryText,
    textAlign: 'left',
  },
  message: {
    fontSize: 15,
    fontWeight: '400',
    color: colors.SecondaryText,
    textAlign: 'left',
  },
  scroll: { flexGrow: 0, flexShrink: 1 },
  buttons: {
    paddingTop: 20,
    paddingBottom: 16,
    paddingHorizontal: 16,
    gap: 10,
  },
});
