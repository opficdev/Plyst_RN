import { StyleSheet, Text, View } from 'react-native';
import { colors } from '../theme';

type HomeEmptyStateProps = { emptyTitle: string; emptyBody: string };
export function HomeEmptyState({ emptyTitle, emptyBody }: HomeEmptyStateProps) {
  return (
    <View style={styles.container}>
      <Text
        style={styles.emptyTitle}
        numberOfLines={0}
        lineBreakStrategyIOS="standard"
      >
        {emptyTitle}
      </Text>
      <Text
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
    fontSize: 15,
    lineHeight: 24,
    color: colors.SecondaryText,
    textAlign: 'center',
    flexShrink: 1,
  },
});
