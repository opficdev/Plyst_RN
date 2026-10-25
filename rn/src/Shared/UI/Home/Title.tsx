import { Image } from 'expo-image';
import { StyleSheet, Text } from 'react-native';
import { colors } from '../../Theme';

// 로고와 제목만 그리며 둘 사이 간격과 배치는 쓰는 쪽이 정함
export function HomeTitle() {
  return (
    <>
      <Image
        source={{ uri: 'HomeLogo' }}
        contentFit="cover"
        style={styles.mark}
      />
      <Text allowFontScaling={false} style={styles.title} numberOfLines={1}>
        Plyst
      </Text>
    </>
  );
}

const styles = StyleSheet.create({
  mark: {
    width: 34,
    height: 34,
    borderRadius: 10,
    overflow: 'hidden',
    flexShrink: 0,
  },
  title: {
    fontSize: 32,
    fontWeight: '800',
    letterSpacing: -1.12,
    color: colors.PrimaryText,
    flexShrink: 1,
  },
});
