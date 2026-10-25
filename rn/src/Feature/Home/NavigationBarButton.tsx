import { StyleSheet } from 'react-native';
import { PlystNavigationBarButton } from 'plyst-bridge';

type NavigationBarButtonProps = {
  side: 'left' | 'right';
  // 지정하면 SF Symbol 항목이고 지정하지 않으면 title 텍스트 항목
  icon?: string;
  title?: string;
  isEnabled?: boolean;
  onPress: () => void;
};

// 항목은 내비게이션 바에 그려지므로 RN 상자는 크기가 없음
export function NavigationBarButton({
  side,
  icon,
  title,
  isEnabled = true,
  onPress,
}: NavigationBarButtonProps) {
  return (
    <PlystNavigationBarButton
      side={side}
      icon={icon}
      title={title}
      isEnabled={isEnabled}
      onPress={onPress}
      style={styles.box}
    />
  );
}

const styles = StyleSheet.create({
  box: { position: 'absolute', width: 0, height: 0 },
});
