import { Image } from 'expo-image';
import { Platform, StyleSheet, Text } from 'react-native';
import { colors } from '../../Theme';

// Android expo-image는 drawable을 이름으로 캐시해 화면 모양이 바뀌어도 처음 그린 모양의 로고를 다시 쓰므로 캐시하지 않음
const logoCachePolicy = Platform.OS === 'android' ? 'none' : undefined;

// 로고와 제목만 그리며 둘 사이 간격과 배치는 쓰는 쪽이 정함
export function HomeTitle() {
  return (
    <>
      <Image source={{ uri: 'HomeLogo' }} contentFit="cover" cachePolicy={logoCachePolicy} style={styles.mark} />
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
