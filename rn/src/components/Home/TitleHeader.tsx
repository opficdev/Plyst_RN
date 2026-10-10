import { Image } from 'expo-image';
import { Pressable, StyleSheet, Text, View } from 'react-native';
import { colors, spacing } from '../../theme';

export function HomeTitleHeader({
  onSearchButtonPress,
  isSearchButtonHidden = false,
}: {
  onSearchButtonPress: () => void;
  isSearchButtonHidden?: boolean;
}) {
  return (
    <View style={styles.container}>
      <Image
        source={{ uri: 'HomeLogo' }}
        contentFit="cover"
        style={styles.mark}
      />
      <Text style={styles.title} numberOfLines={1}>
        Plyst
      </Text>
      <Pressable
        style={[styles.searchButton, isSearchButtonHidden && styles.hidden]}
        disabled={isSearchButtonHidden}
        onPress={onSearchButtonPress}
      >
        <Image
          source="sf:magnifyingglass"
          contentFit="contain"
          style={styles.searchIcon}
        />
      </Pressable>
    </View>
  );
}
const styles = StyleSheet.create({
  container: {
    height: 57,
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: spacing.screen,
    paddingBottom: 13,
    marginTop: -5,
    gap: 10,
  },
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
  hidden: { opacity: 0 },
  searchButton: {
    marginLeft: 'auto',
    width: 44,
    height: 44,
    flexShrink: 0,
    borderRadius: 22,
    borderWidth: 1,
    borderColor: colors.Outline,
    backgroundColor: colors.Card,
    alignItems: 'center',
    justifyContent: 'center',
  },
  // 원본 헤더 검색 아이콘(pointSize 17)의 화면 실측 크기는 약 22pt다.
  // contain은 글리프를 박스에 맞춰 확대하므로 실측 크기에 맞게 박스 크기를 28로 정했다.
  searchIcon: {
    width: 28,
    height: 28,
    fontSize: 17,
    fontWeight: '600',
    color: colors.PrimaryText,
  },
});
