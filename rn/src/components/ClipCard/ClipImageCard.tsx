import { StyleSheet, Text, View } from 'react-native';
import { colors, radius, spacing, typography } from '../../theme';
import type { ClipCardProps } from './ClipCardProps';
import { ClipThumbnail } from './ClipThumbnail';
import { CopyButton } from './CopyButton';

type ClipImageCardProps = ClipCardProps & { thumbnailUri: string | null };
export function ClipImageCard({
  name,
  metadata,
  thumbnailUri,
  onCopyButtonPress,
}: ClipImageCardProps) {
  return (
    <View style={styles.card}>
      <ClipThumbnail uri={thumbnailUri} />
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
          >
            {metadata}
          </Text>
          {onCopyButtonPress && (
            <CopyButton onCopyButtonPress={onCopyButtonPress} />
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
