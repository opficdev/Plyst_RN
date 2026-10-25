import { Platform, StyleSheet } from 'react-native';
import { PlystDetailBarButton } from 'plyst-bridge';

// 크기는 네이티브 DetailBarButton.makeLayout()의 값을 따름
// Yoga는 UIButton의 고유 크기를 모르므로 상자 크기를 여기서 정함
const usesGlass = Number.parseInt(String(Platform.Version), 10) >= 26;
const side = usesGlass ? 44 : 40;
// 저장 버튼 폭은 15pt 두 글자와 좌우 여백 16 두 개의 추정값이며 lldb 실측으로 확정함
export const detailBarTextButtonWidth = 62;
export const detailBarButtonHeight = side;

type DetailBarButtonProps = {
  icon?: string;
  title?: string;
  isEnabled?: boolean;
  onPress: () => void;
};

export function DetailBarButton({
  icon,
  title,
  isEnabled = true,
  onPress,
}: DetailBarButtonProps) {
  return (
    <PlystDetailBarButton
      icon={icon}
      title={title}
      isEnabled={isEnabled}
      onPress={onPress}
      style={[
        styles.box,
        { width: icon === undefined ? detailBarTextButtonWidth : side },
      ]}
    />
  );
}

const styles = StyleSheet.create({
  box: { height: side },
});
