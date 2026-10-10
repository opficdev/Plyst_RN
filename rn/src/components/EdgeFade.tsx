import { StyleSheet, View } from 'react-native';
import { colors } from '../theme';

export function EdgeFade({ height }: { height: number }) {
  return <View pointerEvents="none" style={[styles.fade, { height }]} />;
}

const styles = StyleSheet.create({
  fade: {
    position: 'absolute',
    left: 0,
    right: 0,
    top: 0,
    // 원본 EdgeFadeView의 위쪽 그라데이션이다.
    // React Native는 transparent를 직전 색상의 알파 0 값으로 변환한다.
    experimental_backgroundImage: [
      {
        type: 'linear-gradient',
        direction: 'to bottom',
        colorStops: [
          { color: colors.Canvas, positions: ['0%'] },
          { color: colors.Canvas, positions: ['65%'] },
          { color: 'transparent', positions: ['100%'] },
        ],
      },
    ],
  },
});
