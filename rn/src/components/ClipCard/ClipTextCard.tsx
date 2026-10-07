import { Image } from 'expo-image';
import { StyleSheet, Text, View } from 'react-native';
import { colors, radius, spacing, typography } from '../../theme';
import type { ClipCardProps } from './ClipCardProps';
import { CopyButton } from './CopyButton';

type ClipTextCardProps = ClipCardProps & { body: string; isWebLink: boolean };
export function ClipTextCard({
  name,
  metadata,
  body,
  isWebLink,
  onCopyButtonPress,
}: ClipTextCardProps) {
  return (
    <View style={styles.card}>
      {isWebLink ? (
        <Image source="sf:globe" contentFit="contain" style={styles.linkIcon} />
      ) : (
        <Text style={styles.quote}>“</Text>
      )}
      {name !== null && (
        <Text
          style={styles.name}
          numberOfLines={2}
          lineBreakStrategyIOS="standard"
        >
          {name}
        </Text>
      )}
      <Text
        style={[
          styles.body,
          name === null ? styles.unnamedBody : styles.namedBody,
        ]}
        numberOfLines={name === null ? 3 : 2}
        lineBreakStrategyIOS="standard"
      >
        {body}
      </Text>
      <View style={styles.metadataRow}>
        <Text style={styles.metadata} numberOfLines={onCopyButtonPress ? 2 : 1}>
          {metadata}
        </Text>
        {onCopyButtonPress && (
          <CopyButton onCopyButtonPress={onCopyButtonPress} />
        )}
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
    paddingTop: 35,
    paddingLeft: 13,
    paddingRight: spacing.card - 1,
    paddingBottom: spacing.card - 1,
  },
  quote: {
    position: 'absolute',
    top: 6,
    left: 13,
    fontFamily: 'Georgia-Bold',
    fontSize: 26,
    color: colors.MarkBackground,
  },
  linkIcon: {
    position: 'absolute',
    top: 11,
    left: 13,
    width: 22,
    height: 22,
    fontSize: 20,
    fontWeight: '600',
    color: colors.MarkBackground,
  },
  name: {
    ...typography.cardName,
    color: colors.PrimaryText,
    flexShrink: 1,
    marginBottom: 6,
  },
  body: { ...typography.cardBody, flexShrink: 1 },
  unnamedBody: { color: colors.PrimaryText },
  namedBody: { color: colors.NamedBodyText },
  metadataRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
    marginTop: 10,
  },
  metadata: {
    flex: 1,
    flexShrink: 1,
    fontFamily: 'ui-monospace',
    fontSize: 10.5,
    fontWeight: '500',
    color: colors.SecondaryText,
  },
});
