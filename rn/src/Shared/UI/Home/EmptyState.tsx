import { StyleSheet, Text, View } from 'react-native';
import { colors } from '../../Theme';

type HomeEmptyStateProps = { emptyTitle: string; emptyBody: string };
export function HomeEmptyState({ emptyTitle, emptyBody }: HomeEmptyStateProps) {
  return (
    <View style={styles.container}>
      <Text
        allowFontScaling={false}
        style={styles.emptyTitle}
        numberOfLines={0}
        lineBreakStrategyIOS="standard"
      >
        {emptyTitle}
      </Text>
      <Text
        allowFontScaling={false}
        style={styles.emptyBody}
        numberOfLines={0}
        lineBreakStrategyIOS="standard"
      >
        {emptyBody}
      </Text>
    </View>
  );
}
const styles = StyleSheet.create({
  container: { alignItems: 'center', gap: 10 },
  emptyTitle: {
    fontSize: 21,
    fontWeight: '700',
    letterSpacing: -0.315,
    color: colors.PrimaryText,
    textAlign: 'center',
    flexShrink: 1,
  },
  emptyBody: {
    // RN은 lineHeight의 남는 높이를 위아래로 나누고 원본 UILabel은 위에 둔다.
    // 15pt 시스템 글꼴의 lineHeight 17.9004를 기준으로 (24 − 17.9004)/2 = 3.05만큼 내린다.
    top: 3.05,
    fontSize: 15,
    lineHeight: 24,
    color: colors.SecondaryText,
    textAlign: 'center',
    flexShrink: 1,
  },
});
