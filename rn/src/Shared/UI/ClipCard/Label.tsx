import { useState } from 'react';
import { PixelRatio, Text, type TextProps } from 'react-native';
import type { ReactNode } from 'react';
import { colors } from '../../Theme';
import type { ClipTextRange } from './CardProps';
import { labelTruncation } from './labelTruncation';
import { hangulWordBreak } from '../hangulWordBreak';

type ClipCardLabelProps = Omit<TextProps, 'children'> & {
  children: string;
  highlights?: ClipTextRange[];
  highlightWeight?: '600' | '700';
};
type LabelState = { text: string; height: number };

// minHeight가 물리 픽셀로 올림되어 그려지는 높이
function pixelCeil(height: number) {
  return Math.ceil(height * PixelRatio.get() - 0.01) / PixelRatio.get();
}
type LabelTruncationState = { text: string; cut: number | null };

export function ClipCardLabel({ children, highlights, highlightWeight, style, onLayout, onTextLayout, numberOfLines, ...props }: ClipCardLabelProps) {
  const [state, setState] = useState<LabelState | null>(null);
  const [truncation, setTruncation] = useState<LabelTruncationState | null>(null);

  const key = JSON.stringify([children, highlights ?? [], highlightWeight]);
  const cut = truncation?.text === key ? truncation.cut : null;
  const text = cut === null ? children : children.slice(0, cut) + '…';
  const parts: ReactNode[] = [];
  let cursor = 0;
  for (const { location, length } of highlights ?? []) {
    if (cut !== null && location + length > cut) continue;
    parts.push(hangulWordBreak(text, cursor, location));
    parts.push(
      <Text
        allowFontScaling={false}
        key={location}
        style={{
          backgroundColor: colors.SearchHighlight,
          fontWeight: highlightWeight,
        }}
      >
        {hangulWordBreak(text, location, location + length)}
      </Text>,
    );
    cursor = location + length;
  }
  parts.push(hangulWordBreak(text, cursor));

  // RN 대체 글꼴로 짧아지는 한글 줄 높이를 맞추고 원본처럼 레이블 높이를 올림
  return (
    <Text
      {...props}
      allowFontScaling={false}
      numberOfLines={numberOfLines}
      onTextLayout={
        numberOfLines && /[\n\r\u2028\u2029]/.test(children)
          ? (event) => {
              const lines = event.nativeEvent.lines;
              setTruncation((previous) =>
                previous?.text === key
                  ? previous
                  : {
                      text: key,
                      cut: labelTruncation(children, lines, numberOfLines),
                    },
              );
              onTextLayout?.(event);
            }
          : onTextLayout
      }
      style={[style, { lineHeight: 17.3333 }, state?.text === key && { minHeight: state.height }]}
      onLayout={(event) => {
        const layoutHeight = event.nativeEvent.layout.height;
        const height = Math.ceil(layoutHeight - 0.01);
        // Android는 dp가 물리 픽셀로 올림되어 minHeight보다 조금 높게 측정되므로 그 차이로는 높이를 다시 올리지 않음
        setState((previous) => (previous?.text === key && (previous.height === height || layoutHeight <= pixelCeil(previous.height) + 0.01) ? previous : { text: key, height }));
        onLayout?.(event);
      }}
    >
      {highlights?.length ? parts : hangulWordBreak(text)}
    </Text>
  );
}
