import { useState } from 'react';
import { Text, type TextProps } from 'react-native';
import type { ReactNode } from 'react';
import { colors } from '../../theme';
import type { ClipTextRange } from './CardProps';

type ClipCardLabelProps = Omit<TextProps, 'children'> & {
  children: string;
  highlights?: ClipTextRange[];
  highlightWeight?: '600' | '700';
};
type LabelState = { text: string; height: number };

export function ClipCardLabel({
  children,
  highlights,
  highlightWeight,
  style,
  onLayout,
  ...props
}: ClipCardLabelProps) {
  const [state, setState] = useState<LabelState | null>(null);

  const key = JSON.stringify([children, highlights ?? [], highlightWeight]);
  const parts: ReactNode[] = [];
  let cursor = 0;
  for (const { location, length } of highlights ?? []) {
    parts.push(children.slice(cursor, location));
    parts.push(
      <Text
        key={location}
        style={{
          backgroundColor: colors.SearchHighlight,
          fontWeight: highlightWeight,
        }}
      >
        {children.slice(location, location + length)}
      </Text>,
    );
    cursor = location + length;
  }
  parts.push(children.slice(cursor));

  // RN 대체 글꼴로 짧아지는 한글 줄 높이를 맞추고 원본처럼 레이블 높이를 올림합니다.
  return (
    <Text
      {...props}
      style={[
        style,
        { lineHeight: 17.3333 },
        state?.text === key && { minHeight: state.height },
      ]}
      onLayout={(event) => {
        const height = Math.ceil(event.nativeEvent.layout.height - 0.01);
        setState((previous) =>
          previous?.text === key && previous.height === height
            ? previous
            : { text: key, height },
        );
        onLayout?.(event);
      }}
    >
      {highlights?.length ? parts : children}
    </Text>
  );
}
