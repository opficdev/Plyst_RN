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
  // 원본 HomeCopyButton 아이콘(pointSize 13)의 화면 실측 크기는 약 18pt다.
  // contain은 글리프를 박스에 맞춰 확대하므로 실측 크기에 맞게 박스 크기를 23으로 정했다.
  icon: {
    width: 23,
    height: 23,
    fontSize: 13,
    fontWeight: '600',
    color: colors.PrimaryText,
  },
});
