import { useRef } from 'react';
import type { RefObject } from 'react';
import type {
  LayoutChangeEvent,
  NativeScrollEvent,
  NativeSyntheticEvent,
  ScrollView,
  View,
} from 'react-native';
import { scrollOffsetToReveal } from './scrollOffsetToReveal';

export function useScrollFieldIntoView() {
  const scrollRef = useRef<ScrollView>(null);
  const contentRef = useRef<View>(null);
  const nameRef = useRef<View>(null);
  const memoRef = useRef<View>(null);
  const focusedRef = useRef<RefObject<View | null> | null>(null);
  const offsetRef = useRef(0);
  const heightRef = useRef(0);
  const requestRef = useRef(0);

  function reveal(field: RefObject<View | null>) {
    const content = contentRef.current;
    const row = field.current;
    const request = ++requestRef.current;
    if (!content || !row || heightRef.current <= 0) return;
    row.measureLayout(content, (_x, top, _width, height) => {
      if (request !== requestRef.current || focusedRef.current !== field)
        return;
      const offset = offsetRef.current;
      const y = scrollOffsetToReveal(
        offset,
        heightRef.current,
        top,
        top + height,
      );
      if (y !== offset) scrollRef.current?.scrollTo({ y, animated: true });
    });
  }

  function revealFocused() {
    if (focusedRef.current) reveal(focusedRef.current);
  }

  function focus(field: RefObject<View | null>) {
    focusedRef.current = field;
    reveal(field);
  }

  function blur(field: RefObject<View | null>) {
    if (focusedRef.current === field) {
      focusedRef.current = null;
      requestRef.current += 1;
    }
  }

  return {
    contentRef,
    nameRef,
    memoRef,
    nameInputProps: {
      onFocus: () => focus(nameRef),
      onBlur: () => blur(nameRef),
    },
    memoInputProps: {
      onFocus: () => focus(memoRef),
      onBlur: () => blur(memoRef),
    },
    revealMemo: () => reveal(memoRef),
    scrollProps: {
      ref: scrollRef,
      keyboardDismissMode: 'interactive' as const,
      keyboardShouldPersistTaps: 'handled' as const,
      alwaysBounceVertical: true,
      scrollEventThrottle: 16,
      onScroll: (event: NativeSyntheticEvent<NativeScrollEvent>) => {
        offsetRef.current = event.nativeEvent.contentOffset.y;
      },
      onLayout: (event: LayoutChangeEvent) => {
        const height = event.nativeEvent.layout.height;
        if (height === heightRef.current) return;
        heightRef.current = height;
        revealFocused();
      },
      onContentSizeChange: revealFocused,
    },
  };
}
