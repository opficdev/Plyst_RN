import { Image } from 'expo-image';
import { StyleSheet, Text, View } from 'react-native';
import { colors } from '../../theme';
import type { ClipCardProps } from './CardProps';
import { ClipThumbnail } from './Thumbnail';
import { CopyButton } from './CopyButton';

type ClipPinnedCardProps = ClipCardProps &
  (
    | { kind: 'text'; body: string; isWebLink: boolean }
    | {
        kind: 'image';
        thumbnailUri: string | null;
        isThumbnailFailed?: boolean;
      }
  );
export function ClipPinnedCard(props: ClipPinnedCardProps) {
  const name =
    props.name ?? (props.kind === 'text' ? props.body : '이름 없는 이미지');
  return (
    <View style={styles.card}>
      {props.kind === 'image' ? (
        <ClipThumbnail
          uri={props.thumbnailUri}
          isFailed={props.isThumbnailFailed}
          isPinned
        />
      ) : (
        <View style={styles.visualBox}>
          {props.isWebLink ? (
            <Image
              source="sf:globe"
              contentFit="contain"
              style={styles.linkIcon}
            />
          ) : (
            <Text style={styles.quote}>“</Text>
          )}
        </View>
      )}
      <View style={styles.textStack}>
        <Text style={styles.name} numberOfLines={1}>
          {name}
        </Text>
        <Text style={styles.metadata} numberOfLines={1}>
          {props.metadata}
        </Text>
      </View>
      {props.onCopyButtonPress && (
        <CopyButton onCopyButtonPress={props.onCopyButtonPress} />
      )}
    </View>
  );
}
const styles = StyleSheet.create({
  card: {
    width: 252,
    height: 76,
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 9,
    borderRadius: 16,
    borderWidth: 1,
    borderColor: colors.Outline,
    backgroundColor: colors.Card,
    overflow: 'hidden',
  },
  visualBox: {
    width: 56,
    height: 56,
    flexShrink: 0,
    borderRadius: 10,
    backgroundColor: colors.ImageBackground,
    alignItems: 'center',
    justifyContent: 'center',
    overflow: 'hidden',
  },
  linkIcon: {
    width: 28,
    height: 28,
    fontSize: 24,
    fontWeight: '600',
    color: colors.MarkBackground,
  },
  quote: {
    fontFamily: 'Georgia-Bold',
    fontSize: 20,
    color: colors.MarkBackground,
    textAlign: 'center',
  },
  textStack: { flex: 1, minWidth: 0, marginLeft: 10, marginRight: 8, gap: 4 },
  name: {
    fontSize: 13,
    fontWeight: '600',
    color: colors.PrimaryText,
    flexShrink: 1,
  },
  metadata: {
    fontFamily: 'ui-monospace',
    fontSize: 9.5,
    fontWeight: '500',
    color: colors.SecondaryText,
    flexShrink: 1,
  },
});
