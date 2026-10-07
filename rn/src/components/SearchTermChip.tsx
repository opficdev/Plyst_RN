import { Image } from 'expo-image';
import { Pressable, StyleSheet, Text, View } from 'react-native';
import { colors, typography } from '../theme';

type SearchTermChipProps = {
  term: string;
  onTermButtonPress: () => void;
  onRemoveButtonPress: () => void;
};
export function SearchTermChip({
  term,
  onTermButtonPress,
  onRemoveButtonPress,
}: SearchTermChipProps) {
  return (
    <View style={styles.chip}>
      <Pressable style={styles.termButton} onPress={onTermButtonPress}>
        <Text style={styles.term} numberOfLines={1}>
          {term}
        </Text>
      </Pressable>
      <Pressable style={styles.removeButton} onPress={onRemoveButtonPress}>
        <Image
          source="sf:xmark"
          contentFit="contain"
          style={styles.removeIcon}
        />
      </Pressable>
    </View>
  );
}
const styles = StyleSheet.create({
  chip: {
    maxWidth: 220,
    alignSelf: 'flex-start',
    flexDirection: 'row',
    alignItems: 'center',
    borderRadius: 18,
    borderWidth: 1,
    borderColor: colors.Outline,
    backgroundColor: colors.Card,
    overflow: 'hidden',
  },
  termButton: {
    flexShrink: 1,
    paddingVertical: 7,
    paddingLeft: 13,
    paddingRight: 4,
  },
  term: { ...typography.label, color: colors.PrimaryText, flexShrink: 1 },
  removeButton: {
    flexShrink: 0,
    paddingVertical: 8,
    paddingLeft: 6,
    paddingRight: 11,
  },
  removeIcon: { fontSize: 10, fontWeight: '700', color: colors.SecondaryText },
});
