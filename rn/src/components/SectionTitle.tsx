import { StyleSheet, Text, View } from 'react-native';
import { colors, spacing, typography } from '../theme';

export function SectionTitle({ title }: { title: string }) {
  return (
    <View style={styles.container}>
      <Text style={styles.title} numberOfLines={1}>
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
    lineHeight: 13.3333, // 원본 UILabel의 높이를 반영한다.
    color: colors.SecondaryText,
    flexShrink: 1,
  },
  rule: { height: 1, flex: 1, backgroundColor: colors.Outline },
});
