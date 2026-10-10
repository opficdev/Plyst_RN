import { useState } from 'react';
import { Text, type TextProps } from 'react-native';

type ClipCardLabelProps = Omit<TextProps, 'children'> & { children: string };
type LabelState = { text: string; height: number };

export function ClipCardLabel({
  children,
  style,
  onLayout,
  ...props
}: ClipCardLabelProps) {
  const [state, setState] = useState<LabelState | null>(null);

  // RN 대체 글꼴로 짧아지는 한글 줄 높이를 맞추고 원본처럼 레이블 높이를 올림합니다.
  return (
    <Text
      {...props}
      style={[
        style,
        { lineHeight: 17.3333 },
        state?.text === children && { minHeight: state.height },
      ]}
      onLayout={(event) => {
        const height = Math.ceil(event.nativeEvent.layout.height - 0.01);
        setState((previous) =>
          previous?.text === children && previous.height === height
            ? previous
            : { text: children, height },
        );
        onLayout?.(event);
      }}
    >
      {children}
    </Text>
  );
}
