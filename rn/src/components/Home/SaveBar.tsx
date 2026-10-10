import { Image } from 'expo-image';
import { Pressable, StyleSheet, Text, View } from 'react-native';
import { colors, radius, spacing, typography } from '../../theme';

type HomeSaveBarProps = {
  isSaving: boolean;
  onSaveButtonPress: () => void;
};

export function HomeSaveBar({ isSaving, onSaveButtonPress }: HomeSaveBarProps) {
  return (
    <View style={styles.bar}>
      <Pressable
        disabled={isSaving}
        onPress={onSaveButtonPress}
        style={({ pressed }) => [
          styles.button,
          (isSaving || pressed) && styles.dimmed,
        ]}
      >
        <View style={styles.icon}>
          <View style={styles.board} />
          <View style={styles.tab} />
          <View style={styles.vertical} />
          <View style={styles.horizontal} />
        </View>
        <Text allowFontScaling={false} style={styles.title}>
          현재 클립보드 저장
        </Text>
      </Pressable>
      <View style={styles.privacyRow}>
        <Image source="sf:lock.fill" contentFit="contain" style={styles.lock} />
        <Text allowFontScaling={false} style={styles.privacy}>
          이 기기에만 저장됩니다
        </Text>
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  bar: { marginHorizontal: spacing.card },
  button: {
    height: 54,
    borderRadius: radius.field,
    backgroundColor: colors.BottomBar,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    gap: 9,
    shadowColor: colors.Shadow,
    shadowOpacity: 0.18,
    shadowRadius: 15,
    shadowOffset: { width: 0, height: 8 },
  },
  dimmed: { opacity: 0.55 },
  title: { ...typography.title, color: colors.BottomText },
  icon: { width: 18, height: 18 },
  // UIKit의 경로 중앙에 그린 테두리를 View의 바깥 경계로 옮깁니다.
  board: {
    position: 'absolute',
    left: 2.65,
    top: 2.15,
    width: 12.7,
    height: 14.7,
    borderWidth: 1.7,
    borderRadius: 3.35,
    borderColor: colors.BottomText,
  },
  tab: {
    position: 'absolute',
    left: 5.75,
    top: 0.75,
    width: 6.5,
    height: 4.5,
    borderWidth: 1.5,
    borderRadius: 1.95,
    borderColor: colors.BottomText,
    backgroundColor: colors.BottomBar,
  },
  vertical: {
    position: 'absolute',
    left: 8.15,
    top: 7.15,
    width: 1.7,
    height: 6.7,
    borderRadius: 0.85,
    backgroundColor: colors.BottomText,
  },
  horizontal: {
    position: 'absolute',
    left: 5.65,
    top: 9.65,
    width: 6.7,
    height: 1.7,
    borderRadius: 0.85,
    backgroundColor: colors.BottomText,
  },
  privacyRow: {
    height: 30,
    marginTop: 4,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    gap: 6,
  },
  lock: { width: 10, height: 12, color: colors.PrivacyText },
  privacy: { fontSize: 12, color: colors.PrivacyText },
});
