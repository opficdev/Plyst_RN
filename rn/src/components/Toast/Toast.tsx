import { useEffect, useRef, useState } from 'react';
import { Animated, Easing, StyleSheet, Text } from 'react-native';
import { colors } from '../../theme';

export type ToastProps = {
  message: string;
  isSuccess: boolean;
  isVisible: boolean;
  onHidden?: () => void;
};

export function Toast({ message, isSuccess, isVisible, onHidden }: ToastProps) {
  const [progress] = useState(() => new Animated.Value(0));
  const hidden = useRef(onHidden);

  useEffect(() => {
    hidden.current = onHidden;
  }, [onHidden]);

  useEffect(() => {
    if (isVisible) progress.setValue(0);
    const animation = Animated.timing(progress, {
      toValue: isVisible ? 1 : 0,
      duration: isVisible ? 250 : 200,
      easing: isVisible
        ? Easing.bezier(0, 0, 0.58, 1)
        : Easing.bezier(0.42, 0, 1, 1),
      useNativeDriver: true,
    });
    animation.start(({ finished }) => {
      if (finished && !isVisible) hidden.current?.();
    });
    return () => animation.stop();
  }, [isVisible, progress]);

  return (
    <Animated.View
      pointerEvents="none"
      style={[
        styles.pill,
        {
          backgroundColor: isSuccess
            ? colors.FeedbackSuccess
            : colors.FeedbackFailure,
          opacity: progress,
          transform: [
            {
              translateY: progress.interpolate({
                inputRange: [0, 1],
                outputRange: [-16, 0],
              }),
            },
          ],
        },
      ]}
    >
      <Text style={styles.message} allowFontScaling={false}>
        {message}
      </Text>
    </Animated.View>
  );
}

const styles = StyleSheet.create({
  pill: {
    maxWidth: '100%',
    borderRadius: 12,
    paddingVertical: 11,
    paddingHorizontal: 14,
  },
  message: {
    color: colors.BottomText,
    fontSize: 14,
    fontWeight: '500',
    textAlign: 'center',
  },
});
