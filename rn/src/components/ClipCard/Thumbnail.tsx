import { Image } from 'expo-image';
import { useState } from 'react';
import { StyleSheet, View } from 'react-native';
import { colors } from '../../theme';

type ClipThumbnailProps = {
  uri: string | null;
  isPinned?: boolean;
  isFailed?: boolean;
};
type ThumbnailState = {
  uri: string | null;
  phase: 'pending' | 'loaded' | 'failed';
};

export function ClipThumbnail({
  uri,
  isPinned = false,
  isFailed = false,
}: ClipThumbnailProps) {
  const [state, setState] = useState<ThumbnailState>({ uri, phase: 'pending' });
  const phase = isFailed
    ? 'failed'
    : state.uri === uri
      ? state.phase
      : 'pending';
  return (
    <View
      style={[styles.imageBox, isPinned ? styles.pinnedBox : styles.cardBox]}
    >
      {uri !== null && (
        <Image
          key={uri}
          source={{ uri }}
          cachePolicy="memory"
          contentFit="contain"
          style={[styles.imageView, phase !== 'loaded' && styles.hidden]}
          onLoad={() => setState({ uri, phase: 'loaded' })}
          onError={() => setState({ uri, phase: 'failed' })}
        />
      )}
      {phase === 'pending' && !isPinned && (
        <View style={styles.placeholder}>
          <View style={styles.placeholderDot} />
        </View>
      )}
      {phase === 'failed' && (
        <Image
          source="sf:exclamationmark.triangle"
          contentFit="contain"
          style={[
            styles.failureIcon,
            isPinned ? styles.pinnedFailureIcon : styles.cardFailureIcon,
          ]}
        />
      )}
    </View>
  );
}
const styles = StyleSheet.create({
  imageBox: {
    backgroundColor: colors.ImageBackground,
    overflow: 'hidden',
    alignItems: 'center',
    justifyContent: 'center',
  },
  cardBox: { aspectRatio: 1, borderRadius: 13 },
  pinnedBox: { width: 56, height: 56, borderRadius: 10, flexShrink: 0 },
  imageView: { ...StyleSheet.absoluteFill },
  hidden: { opacity: 0 },
  placeholder: {
    width: 24,
    height: 18,
    borderRadius: 3,
    borderWidth: 1.5,
    borderColor: colors.Placeholder,
  },
  placeholderDot: {
    position: 'absolute',
    top: 2.5,
    left: 3.5,
    width: 5,
    height: 5,
    borderRadius: 2.5,
    backgroundColor: colors.Placeholder,
  },
  failureIcon: { color: colors.Placeholder, fontWeight: '400' },
  cardFailureIcon: { fontSize: 28 },
  pinnedFailureIcon: { fontSize: 22 },
});
