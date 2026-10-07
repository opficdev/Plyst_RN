import { Image } from 'expo-image';
import { Pressable, StyleSheet, Text, View } from 'react-native';
import { colors, spacing } from '../theme';

export function HomeTitleHeader({
  onSearchButtonPress,
}: {
  onSearchButtonPress: () => void;
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
      <Pressable style={styles.searchButton} onPress={onSearchButtonPress}>
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
  searchIcon: { fontSize: 17, fontWeight: '600', color: colors.PrimaryText },
});
