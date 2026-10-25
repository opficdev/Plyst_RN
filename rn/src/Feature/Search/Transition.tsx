import type { ViewProps } from 'react-native';
import { PlystSearchTransition } from 'plyst-bridge';

export type SearchTransitionProps = ViewProps & {
  effect: 'fadeIn' | 'fadeOut' | 'expand';
  isPresented: boolean;
  onTransitionEnd?: (isPresented: boolean) => void;
};

// 네이티브가 자기 layer의 알파를 정하므로 style에 opacity를 넘기지 않음
export function SearchTransition({
  onTransitionEnd,
  ...props
}: SearchTransitionProps) {
  return (
    <PlystSearchTransition
      {...props}
      onTransitionEnd={
        onTransitionEnd &&
        ((event) => onTransitionEnd(event.nativeEvent.isPresented))
      }
    />
  );
}
