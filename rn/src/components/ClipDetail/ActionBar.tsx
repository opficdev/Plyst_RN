import { Image } from 'expo-image';
import { Pressable, StyleSheet, Text, View } from 'react-native';
import { colors, radius, spacing } from '../../theme';

type ClipDetailActionBarProps = {
  isBusy?: boolean;
  onDeleteButtonPress: () => void;
  onCopyButtonPress: () => void;
};
export function ClipDetailActionBar({
  isBusy = false,
  onDeleteButtonPress,
  onCopyButtonPress,
}: ClipDetailActionBarProps) {
  return (
    <View style={styles.container}>
      <View style={styles.line} />
      <View style={[styles.stack, isBusy && styles.busy]}>
        <Pressable
          style={styles.deleteButton}
          disabled={isBusy}
          onPress={onDeleteButtonPress}
        >
          <Text style={styles.deleteTitle} numberOfLines={1}>
            삭제
          </Text>
        </Pressable>
        <Pressable
          style={styles.copyButton}
          disabled={isBusy}
          onPress={onCopyButtonPress}
        >
          <Image
            source="sf:doc.on.doc"
            contentFit="contain"
            style={styles.copyIcon}
          />
          <Text style={styles.copyTitle} numberOfLines={1}>
            다시 복사
          </Text>
        </Pressable>
      </View>
    </View>
  );
}
const styles = StyleSheet.create({
  container: {
    backgroundColor: colors.Canvas,
    paddingVertical: 12,
    paddingHorizontal: spacing.detail,
  },
  line: {
    position: 'absolute',
    top: 0,
    left: 0,
    right: 0,
    height: 1,
    backgroundColor: colors.Outline,
  },
  stack: { flexDirection: 'row', gap: 10 },
  busy: { opacity: 0.55 },
  deleteButton: {
    width: 84,
    height: 54,
    flexShrink: 0,
    borderRadius: radius.button,
    borderWidth: 1,
    borderColor: colors.Outline,
    backgroundColor: colors.Card,
    alignItems: 'center',
    justifyContent: 'center',
    paddingHorizontal: 8,
  },
  copyButton: {
    flex: 1,
    height: 54,
    borderRadius: radius.button,
    backgroundColor: colors.BottomBar,
    flexDirection: 'row',
    gap: 8,
    alignItems: 'center',
    justifyContent: 'center',
    paddingHorizontal: 8,
  },
  deleteTitle: {
    fontSize: 16,
    fontWeight: '600',
    color: colors.FeedbackFailure,
    flexShrink: 1,
  },
  copyTitle: {
    fontSize: 17,
    fontWeight: '600',
    color: colors.BottomText,
    flexShrink: 1,
  },
  // 원본 액션 바 복사 아이콘(pointSize 15)의 화면 실측 크기는 약 20pt다.
  // contain은 글리프를 박스에 맞춰 확대하므로 실측 크기에 맞게 박스 크기를 27로 정했다.
  copyIcon: {
    width: 27,
    height: 27,
    fontSize: 15,
    fontWeight: '600',
    color: colors.BottomText,
    flexShrink: 0,
  },
});
