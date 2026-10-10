import {
  useCallback,
  useEffect,
  useLayoutEffect,
  useRef,
  useState,
} from 'react';
import type { RefObject } from 'react';
import { Animated, Easing } from 'react-native';
import type { NativeScrollEvent, NativeSyntheticEvent } from 'react-native';
import type { FlashListRef } from '@shopify/flash-list';
import {
  homeHeaderSnapDuration,
  homeScrollToTop,
  reloadHeaderPosition,
  snapHeaderTarget,
  updateHeaderHidden,
} from './homeHeaderScroll';
import type {
  HomeHeaderPosition,
  HomeScrollGeometry,
} from './homeHeaderScroll';
import type { HomeListItem } from './homeListItems';

type ScrollEvent = NativeSyntheticEvent<NativeScrollEvent>;

export function useHomeHeaderScroll(
  list: RefObject<FlashListRef<HomeListItem> | null>,
  geometry: HomeScrollGeometry,
  content: HomeListItem[],
) {
  const [translateY] = useState(() => new Animated.Value(0));
  const position = useRef<HomeHeaderPosition>({
    hidden: 0,
    previousScrollY: null,
  });
  const current = useRef(geometry);
  const offset = useRef(0);
  const dragging = useRef(false);
  const decelerating = useRef(false);
  const updating = useRef(false);
  const timer = useRef<ReturnType<typeof setTimeout> | undefined>(undefined);
  const animation = useRef<Animated.CompositeAnimation | null>(null);
  const [indicatorTop, setIndicatorTop] = useState(geometry.headerHeight);

  const stop = useCallback(() => {
    clearTimeout(timer.current);
    animation.current?.stop();
    animation.current = null;
    updating.current = false;
  }, []);

  useLayoutEffect(() => {
    const previous = current.current;
    current.current = geometry;
    stop();
    const hidden =
      previous.headerHeight === 0
        ? 0
        : (position.current.hidden * geometry.headerHeight) /
          previous.headerHeight;
    const next = reloadHeaderPosition(hidden, offset.current, geometry);
    position.current = next;
    translateY.setValue(-next.hidden);
    if (!next.isScrollEnabled) {
      offset.current = next.contentOffset;
      list.current?.scrollToOffset({
        offset: next.contentOffset,
        animated: false,
        skipFirstItemOffset: true,
      });
    }
    if (
      previous.headerHeight !== geometry.headerHeight ||
      !next.isScrollEnabled
    )
      setIndicatorTop(geometry.headerHeight - next.hidden);
  }, [geometry, content, list, stop, translateY]);

  useEffect(() => {
    const listener = translateY.addListener(({ value }) => {
      position.current.hidden = -value;
    });
    return () => {
      stop();
      translateY.removeListener(listener);
    };
  }, [stop, translateY]);

  const reset = useCallback(() => {
    stop();
    const next = homeScrollToTop(current.current.insetTop);
    position.current = next;
    offset.current = next.contentOffset;
    translateY.setValue(0);
    setIndicatorTop(current.current.headerHeight);
    list.current?.scrollToOffset({
      offset: next.contentOffset,
      animated: true,
      skipFirstItemOffset: true,
    });
  }, [list, stop, translateY]);

  function snap() {
    if (updating.current) return;
    const target = snapHeaderTarget(
      position.current.hidden,
      offset.current,
      current.current,
    );
    setIndicatorTop(
      current.current.headerHeight -
        (target?.hidden ?? position.current.hidden),
    );
    if (!target) return;
    updating.current = true;
    animation.current = Animated.timing(translateY, {
      toValue: -target.hidden,
      duration: homeHeaderSnapDuration * 1000,
      easing: Easing.out(Easing.cubic),
      useNativeDriver: false,
    });
    list.current?.scrollToOffset({
      offset: target.scrollY,
      animated: true,
      skipFirstItemOffset: true,
    });
    animation.current.start(({ finished }) => {
      updating.current = false;
      if (finished) {
        offset.current = target.scrollY;
        position.current.previousScrollY = target.scrollY;
      }
    });
  }

  return {
    translateY,
    indicatorTop,
    reset,
    onScroll(event: ScrollEvent) {
      offset.current = event.nativeEvent.contentOffset.y;
      position.current = updateHeaderHidden(
        position.current,
        offset.current,
        current.current,
        dragging.current,
        decelerating.current,
        updating.current,
      );
      if (!updating.current) translateY.setValue(-position.current.hidden);
    },
    onScrollBeginDrag(event: ScrollEvent) {
      stop();
      dragging.current = true;
      decelerating.current = false;
      position.current.previousScrollY = event.nativeEvent.contentOffset.y;
    },
    onScrollEndDrag(event: ScrollEvent) {
      offset.current = event.nativeEvent.contentOffset.y;
      dragging.current = false;
      timer.current = setTimeout(() => {
        if (!decelerating.current) snap();
      }, 0);
    },
    onMomentumScrollBegin() {
      clearTimeout(timer.current);
      decelerating.current = true;
    },
    onMomentumScrollEnd(event: ScrollEvent) {
      offset.current = event.nativeEvent.contentOffset.y;
      decelerating.current = false;
      snap();
    },
  };
}
