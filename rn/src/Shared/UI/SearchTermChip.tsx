import { Image } from 'expo-image';
import { Pressable, StyleSheet, Text, View } from 'react-native';
import { colors, typography } from '../Theme';

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
        <Text style={styles.term} numberOfLines={1} allowFontScaling={false}>
          {term}
        </Text>
      </Pressable>
      <Pressable style={styles.removeButton} onPress={onRemoveButtonPress}>
        <Image source="sf:xmark" contentFit="none" style={styles.removeIcon} />
      </Pressable>
    </View>
  );
}
const styles = StyleSheet.create({
  chip: {
    maxWidth: 220,
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
  term: {
    ...typography.label,
    // RN은 한글만 있는 줄에 대체 글꼴 높이를 써서 짧아짐
    // 원본 13pt UILabel의 줄 높이 15.6667을 쓰되 3x 격자에서 올림되지 않도록 15.6666으로 둠
    lineHeight: 15.6666,
    color: colors.PrimaryText,
    flexShrink: 1,
  },
  removeButton: {
    flexShrink: 0,
    paddingVertical: 8,
    paddingLeft: 6,
    paddingRight: 11,
  },
  // 원본 xmark 이미지 뷰를 lldb로 잰 크기
  removeIcon: {
    width: 14,
    height: 12.6667,
    fontSize: 10,
    fontWeight: '700',
    color: colors.SecondaryText,
  },
});
