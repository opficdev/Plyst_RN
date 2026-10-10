import { StyleSheet, Text, View } from 'react-native';
import { colors, radius, spacing, typography } from '../../theme';
import type { ClipCardProps } from './CardProps';
import { ClipThumbnail } from './Thumbnail';
import { CopyButton } from './CopyButton';

type ClipImageCardProps = ClipCardProps & {
  thumbnailUri: string | null;
  isThumbnailFailed?: boolean;
};
export function ClipImageCard({
  name,
  metadata,
  thumbnailUri,
  isThumbnailFailed,
  onCopyButtonPress,
  onCopyButtonLongPress,
}: ClipImageCardProps) {
  return (
    <View style={styles.card}>
      <View style={styles.thumbnailInset}>
        <ClipThumbnail uri={thumbnailUri} isFailed={isThumbnailFailed} />
      </View>
      <View style={styles.content}>
        <Text
          style={[styles.name, name === null && styles.unnamed]}
          numberOfLines={2}
          lineBreakStrategyIOS="standard"
        >
          {name ?? '이름 없는 이미지'}
        </Text>
        <View style={styles.metadataRow}>
          <Text
            style={styles.metadata}
            numberOfLines={onCopyButtonPress ? 2 : 1}
            lineBreakStrategyIOS="hangul-word"
          >
            {metadata}
          </Text>
          {onCopyButtonPress && (
            <CopyButton
              onCopyButtonPress={onCopyButtonPress}
              onCopyButtonLongPress={onCopyButtonLongPress}
            />
          )}
        </View>
      </View>
    </View>
  );
}
const styles = StyleSheet.create({
  card: {
    backgroundColor: colors.Card,
    borderColor: colors.Outline,
    borderWidth: 1,
    borderRadius: radius.card,
    overflow: 'hidden',
  },
  // margin이 정사각형 상자의 너비를 줄이지 않도록 바깥 View에 여백을 둡니다.
  thumbnailInset: { padding: 5, paddingBottom: 0 },
  content: {
    paddingLeft: 13,
    paddingRight: spacing.card - 1,
    paddingBottom: spacing.card - 1,
    paddingTop: 10,
    gap: 10,
  },
  name: { ...typography.cardName, color: colors.PrimaryText, flexShrink: 1 },
  unnamed: { color: colors.UnnamedText },
  metadataRow: { flexDirection: 'row', alignItems: 'center', gap: 8 },
  metadata: {
    flex: 1,
    flexShrink: 1,
    fontFamily: 'ui-monospace',
    fontSize: 10.5,
    fontWeight: '500',
    color: colors.SecondaryText,
  },
});
