import { StyleSheet, Text, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { colors } from '../../Shared/Theme';
import { DetailBarButton, detailBarButtonHeight } from './BarButton';

type ClipDetailTopBarProps = {
  title: string;
  isSaveEnabled: boolean;
  onCloseButtonPress: () => void;
  onSaveButtonPress: () => void;
};

export function ClipDetailTopBar({
  title,
  isSaveEnabled,
  onCloseButtonPress,
  onSaveButtonPress,
}: ClipDetailTopBarProps) {
  const insets = useSafeAreaInsets();
  return (
    <View style={[styles.bar, { paddingTop: insets.top + 12 }]}>
      <DetailBarButton icon="xmark" onPress={onCloseButtonPress} />
      <DetailBarButton
        title="저장"
        isEnabled={isSaveEnabled}
        onPress={onSaveButtonPress}
      />
      <View
        pointerEvents="none"
        style={[styles.title, { top: insets.top + 12 }]}
      >
        <Text allowFontScaling={false} style={styles.titleText}>
          {title}
        </Text>
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  // 글래스 버튼의 그림자가 아래 내용에 잘리지 않도록 위에 두고 overflow를 자르지 않음
  bar: {
    zIndex: 1,
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'flex-start',
    paddingHorizontal: 16,
    paddingBottom: 8,
    backgroundColor: 'transparent',
  },
  title: {
    position: 'absolute',
    left: 0,
    right: 0,
    height: detailBarButtonHeight,
    alignItems: 'center',
    justifyContent: 'center',
  },
  titleText: { fontSize: 17, fontWeight: '600', color: colors.PrimaryText },
});
