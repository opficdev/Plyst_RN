import { useRef, useState } from 'react';
import type { ReactNode } from 'react';
import {
  KeyboardAvoidingView,
  Modal,
  StyleSheet,
  View,
  useWindowDimensions,
} from 'react-native';
import {
  SafeAreaProvider,
  useSafeAreaInsets,
} from 'react-native-safe-area-context';
import { colors } from '../../Shared/Theme';
import {
  initialSheetVisibility,
  isSheetVisible,
  reduceSheetVisibility,
} from './sheetVisibility';
import { ClipDetailTopBar } from './TopBar';

type ClipDetailSheetProps = {
  title: string;
  isSaveEnabled: boolean;
  // 화면이 저장, 삭제, 조회 실패로 닫혀야 하면 true입니다.
  isClosed: boolean;
  onSaveButtonPress: () => void;
  // Modal의 dismiss가 끝난 뒤 또는 스와이프로 닫힌 뒤에 한 번만 호출합니다.
  onDismiss: () => void;
  children: ReactNode;
};

// 시트를 닫는 요청은 isClosed나 닫기 버튼으로만 하고 onDismiss는 닫힘이 끝난 뒤의 알림입니다.
export function ClipDetailSheet({
  title,
  isSaveEnabled,
  isClosed,
  onSaveButtonPress,
  onDismiss,
  children,
}: ClipDetailSheetProps) {
  const [visibility, setVisibility] = useState(initialSheetVisibility);
  const didFinish = useRef(false);
  function finish() {
    if (didFinish.current) return;
    didFinish.current = true;
    onDismiss();
  }
  return (
    <Modal
      visible={isSheetVisible(visibility, isClosed)}
      presentationStyle="pageSheet"
      animationType="slide"
      allowSwipeDismissal
      backdropColor={colors.Canvas}
      onShow={() => setVisibility((v) => reduceSheetVisibility(v, 'shown'))}
      onDismiss={finish}
      onRequestClose={() => {
        setVisibility((v) => reduceSheetVisibility(v, 'swiped'));
        finish();
      }}
    >
      <SafeAreaProvider style={styles.canvas}>
        <SheetBody
          title={title}
          isSaveEnabled={isSaveEnabled}
          onCloseButtonPress={() =>
            setVisibility((v) => reduceSheetVisibility(v, 'closeRequested'))
          }
          onSaveButtonPress={onSaveButtonPress}
        >
          {children}
        </SheetBody>
      </SafeAreaProvider>
    </Modal>
  );
}

type SheetBodyProps = {
  title: string;
  isSaveEnabled: boolean;
  onCloseButtonPress: () => void;
  onSaveButtonPress: () => void;
  children: ReactNode;
};

const contentMetrics = {
  insets: { top: 0, left: 0, bottom: 0, right: 0 },
  frame: { x: 0, y: 0, width: 0, height: 0 },
};

function SheetBody({
  title,
  isSaveEnabled,
  onCloseButtonPress,
  onSaveButtonPress,
  children,
}: SheetBodyProps) {
  const insets = useSafeAreaInsets();
  const window = useWindowDimensions();
  const [height, setHeight] = useState(0);
  return (
    <View
      style={styles.canvas}
      onLayout={({ nativeEvent: { layout } }) => setHeight(layout.height)}
    >
      <ClipDetailTopBar
        title={title}
        isSaveEnabled={isSaveEnabled}
        onCloseButtonPress={onCloseButtonPress}
        onSaveButtonPress={onSaveButtonPress}
      />
      {/* 시트는 창 아래에 붙어 있으므로 시트의 창 안 y는 창 높이에서 시트 높이를 뺀 값입니다. */}
      <KeyboardAvoidingView
        behavior="padding"
        keyboardVerticalOffset={Math.max(0, window.height - height)}
        style={[styles.content, { marginBottom: insets.bottom }]}
      >
        {/* 내용 영역은 상단 바 아래부터 안전 영역 하단까지이므로 안전 영역 여백이 0입니다. */}
        <SafeAreaProvider
          initialMetrics={contentMetrics}
          style={styles.content}
        >
          {children}
        </SafeAreaProvider>
      </KeyboardAvoidingView>
    </View>
  );
}

const styles = StyleSheet.create({
  canvas: { flex: 1, backgroundColor: colors.Canvas },
  content: { flex: 1 },
});
