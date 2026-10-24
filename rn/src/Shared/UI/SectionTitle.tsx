import { StyleSheet, Text, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { colors, spacing, typography } from '../Theme';

export function SectionTitle({ title }: { title: string }) {
  // 오른쪽 safe area가 있으면 목록 틀이 safe area 안으로 16 들어옴
  // 이때는 오른쪽 여백을 16으로 줄여 구분선을 safe area 경계에서 끝냄
  const isRightInset = 0 < useSafeAreaInsets().right;
  return (
    <View style={[styles.container, isRightInset && styles.insetContainer]}>
      <Text allowFontScaling={false} style={styles.title} numberOfLines={1}>
        {title}
      </Text>
      <View style={styles.rule} />
    </View>
  );
}
const styles = StyleSheet.create({
  container: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 10,
    paddingTop: spacing.screen,
    paddingHorizontal: spacing.screen,
  },
  title: {
    ...typography.sectionLabel,
    lineHeight: 13.3333, // 원본 UILabel의 높이를 반영함
    color: colors.SecondaryText,
    flexShrink: 1,
  },
  rule: { height: 1, flex: 1, backgroundColor: colors.Outline },
  insetContainer: { paddingRight: 16 },
});
