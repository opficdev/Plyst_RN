import { useEffect, useState } from 'react';
import type { ReactNode } from 'react';
import {
  KeyboardAvoidingView,
  StyleSheet,
  View,
  useWindowDimensions,
} from 'react-native';
import {
  SafeAreaProvider,
  useSafeAreaInsets,
} from 'react-native-safe-area-context';
import { ScreenStackItem } from 'react-native-screens';
import type { ScreenStackHeaderConfigProps } from 'react-native-screens';
import { colors } from '../../Shared/Theme';
import { NavigationBarButton } from './NavigationBarButton';
import { ClipDetailTopBar } from './TopBar';

type ClipDetailSheetProps = {
  title: string;
  // true이면 시스템 내비게이션 바가 닫기, 제목, 저장을 그리고 false이면 RN 상단 바가 그립니다.
  usesSystemBar: boolean;
  isSaveEnabled: boolean;
  // 화면이 저장, 삭제, 조회 실패로 닫혀야 하면 true입니다.
  isClosed: boolean;
  onSaveButtonPress: () => void;
  // 닫기 버튼, 스와이프, isClosed 중 먼저 온 것으로 한 번 이상 호출하며 여러 번 호출해도 같은 결과여야 합니다.
  onClose: () => void;
  children: ReactNode;
};

// 시트는 스택 항목이므로 부모가 항목을 빼면 시스템이 dismiss합니다. 그래서 닫기 요청은 곧 onClose입니다.
export function ClipDetailSheet({
  title,
  usesSystemBar,
  isSaveEnabled,
  isClosed,
  onSaveButtonPress,
  onClose,
  children,
}: ClipDetailSheetProps) {
  useEffect(() => {
    if (isClosed) onClose();
  }, [isClosed, onClose]);
  const headerConfig: ScreenStackHeaderConfigProps = {
    hidden: !usesSystemBar,
    title,
    titleColor: colors.PrimaryText,
    backgroundColor: colors.Canvas,
    hideShadow: true,
  };
  return (
    <ScreenStackItem
      screenId="clipDetail"
      stackPresentation="pageSheet"
      headerConfig={headerConfig}
      onDismissed={onClose}
      style={StyleSheet.absoluteFill}
    >
      <SafeAreaProvider style={styles.canvas}>
        <SheetBody
          title={title}
          usesSystemBar={usesSystemBar}
          isSaveEnabled={isSaveEnabled}
          onCloseButtonPress={onClose}
          onSaveButtonPress={onSaveButtonPress}
        >
          {children}
        </SheetBody>
      </SafeAreaProvider>
    </ScreenStackItem>
  );
}

type SheetBodyProps = {
  title: string;
  usesSystemBar: boolean;
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
  usesSystemBar,
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
      {usesSystemBar ? (
        <>
          <NavigationBarButton
            side="left"
            icon="xmark"
            onPress={onCloseButtonPress}
          />
          <NavigationBarButton
            side="right"
            title="저장"
            isEnabled={isSaveEnabled}
            onPress={onSaveButtonPress}
          />
        </>
      ) : (
        <ClipDetailTopBar
          title={title}
          isSaveEnabled={isSaveEnabled}
          onCloseButtonPress={onCloseButtonPress}
          onSaveButtonPress={onSaveButtonPress}
        />
      )}
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
