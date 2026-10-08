import { StyleSheet, Text, View } from 'react-native';
import { colors } from '../../theme';

type ClipDetailDatesProps = { savedValue: string; lastUsedValue: string };
export function ClipDetailDates({
  savedValue,
  lastUsedValue,
}: ClipDetailDatesProps) {
  return (
    <View style={styles.container}>
      <View style={styles.cell}>
        <Text style={styles.caption} numberOfLines={1}>
          저장한 날짜
        </Text>
        <Text style={styles.value} numberOfLines={0}>
          {savedValue}
        </Text>
      </View>
      <View style={styles.cell}>
        <Text style={styles.caption} numberOfLines={1}>
          마지막 사용
        </Text>
        <Text style={styles.value} numberOfLines={0}>
          {lastUsedValue}
        </Text>
      </View>
    </View>
  );
}
const styles = StyleSheet.create({
  container: {
    flexDirection: 'row',
    gap: 1,
    borderRadius: 14,
    borderWidth: 1,
    borderColor: colors.Outline,
    backgroundColor: colors.Outline,
    overflow: 'hidden',
  },
  cell: {
    flex: 1,
    minWidth: 0,
    backgroundColor: colors.Card,
    paddingVertical: 11,
    paddingHorizontal: 13,
    gap: 4,
  },
  caption: { fontSize: 12, color: colors.SecondaryText, flexShrink: 1 },
  value: {
    fontFamily: 'ui-monospace',
    fontSize: 14,
    fontWeight: '500',
    color: colors.PrimaryText,
    flexShrink: 1,
  },
});
