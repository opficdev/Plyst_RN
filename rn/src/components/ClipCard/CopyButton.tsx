import { Image } from 'expo-image';
import { Pressable, StyleSheet } from 'react-native';
import { colors } from '../../theme';

export function CopyButton({
  onCopyButtonPress,
}: {
  onCopyButtonPress: () => void;
}) {
  return (
    <Pressable style={styles.copyButton} onPress={onCopyButtonPress}>
      <Image source="sf:doc.on.doc" contentFit="contain" style={styles.icon} />
    </Pressable>
  );
}
const styles = StyleSheet.create({
  copyButton: {
    width: 32,
    height: 32,
    flexShrink: 0,
    borderRadius: 10,
    backgroundColor: colors.ImageBackground,
    alignItems: 'center',
    justifyContent: 'center',
  },
  icon: { fontSize: 13, fontWeight: '600', color: colors.PrimaryText },
});
