import { useEffect, useState } from 'react';
import { Animated, Easing, Platform, Pressable, StyleSheet, Switch } from 'react-native';
import { colors } from '../../Theme';

type ClipDetailPinSwitchProps = { value: boolean; onValueChange: (value: boolean) => void };

// iOS는 UISwitch를 그리고 Android는 Material 스위치 대신 같은 모양의 스위치를 그림
export function ClipDetailPinSwitch({ value, onValueChange }: ClipDetailPinSwitchProps) {
  if (Platform.OS !== 'android') {
    return <Switch value={value} onValueChange={onValueChange} trackColor={{ true: colors.SwitchOn }} />;
  }
  return <CapsuleSwitch value={value} onValueChange={onValueChange} />;
}

// iOS 26 이후 UISwitch의 실측 크기
const trackWidth = 63;
const trackHeight = 28;
const thumbWidth = 37;
const thumbInset = 2;
const thumbTravel = trackWidth - thumbWidth - thumbInset * 2;

// PlatformColor는 보간할 수 없어 켜진 트랙을 꺼진 트랙 위에 겹쳐 불투명도로 바꿈
function CapsuleSwitch({ value, onValueChange }: ClipDetailPinSwitchProps) {
  const [progress] = useState(() => new Animated.Value(value ? 1 : 0));
  useEffect(() => {
    Animated.timing(progress, {
      toValue: value ? 1 : 0,
      duration: 250,
      easing: Easing.inOut(Easing.ease),
      useNativeDriver: true,
    }).start();
  }, [progress, value]);
  return (
    <Pressable style={styles.track} onPress={() => onValueChange(!value)}>
      <Animated.View style={[StyleSheet.absoluteFill, styles.onTrack, { opacity: progress }]} />
      <Animated.View style={[styles.thumb, { transform: [{ translateX: Animated.multiply(progress, thumbTravel) }] }]} />
    </Pressable>
  );
}

const styles = StyleSheet.create({
  track: {
    width: trackWidth,
    height: trackHeight,
    borderRadius: trackHeight / 2,
    backgroundColor: colors.SwitchOff,
    overflow: 'hidden',
  },
  onTrack: { backgroundColor: colors.SwitchOn },
  thumb: {
    position: 'absolute',
    top: thumbInset,
    left: thumbInset,
    width: thumbWidth,
    height: trackHeight - thumbInset * 2,
    borderRadius: (trackHeight - thumbInset * 2) / 2,
    backgroundColor: colors.SwitchThumb,
  },
});
