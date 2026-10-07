import { Pressable, StyleSheet, Text } from 'react-native';
import { colors, typography } from '../../theme';
import type { ActionSheetItem } from './ActionSheetItem';

type ActionSheetButtonProps = {
  title: string;
  role: ActionSheetItem['role'];
  onPress: () => void;
};
export function ActionSheetButton({
  title,
  role,
  onPress,
}: ActionSheetButtonProps) {
  return (
    <Pressable
      style={({ pressed }) => [styles.button, pressed && styles.pressed]}
      onPress={onPress}
    >
      <Text
        style={[styles.title, role === 'destructive' && styles.destructive]}
        lineBreakStrategyIOS="standard"
      >
        {title}
      </Text>
    </Pressable>
  );
}
const styles = StyleSheet.create({
  button: {
    borderRadius: 999,
    backgroundColor: colors.Outline,
    minHeight: 52,
    paddingVertical: 14,
    paddingHorizontal: 20,
    alignItems: 'center',
    justifyContent: 'center',
    alignSelf: 'stretch',
  },
  pressed: { opacity: 0.6 },
  title: {
    ...typography.title,
    color: colors.PrimaryText,
    textAlign: 'center',
  },
  destructive: { color: colors.FeedbackFailure },
});
