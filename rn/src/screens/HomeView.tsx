import { useEffect, useMemo, useReducer, useRef, useState } from 'react';
import { Animated, PixelRatio, StyleSheet, View } from 'react-native';
import {
  SafeAreaProvider,
  useSafeAreaInsets,
} from 'react-native-safe-area-context';
import { FlashList } from '@shopify/flash-list';
import type { FlashListRef } from '@shopify/flash-list';
import { openClip, openSearch } from 'plyst-bridge';
import {
  ClipTextCard,
  ClipImageCard,
  EdgeFade,
  HomeEmptyState,
  HomeFilterBar,
  HomePinnedRow,
  HomeTitleHeader,
  SectionTitle,
} from '../components';
import { colors } from '../theme';
import { HomeGridCard, HomeListCell } from './HomeGridCard';
import {
  homeEmptyState,
  homeFilters,
  homeFilterStrings,
  homeSectionTitles,
  makeHomeContent,
} from './homeContent';
import {
  homeCardValues,
  homeColumnWidth,
  homeThumbnailPixels,
} from './homeCardValues';
import { makeHomeListItems } from './homeListItems';
import type { HomeListItem } from './homeListItems';
import { initialState, reduce } from './homeState';
import { useHomeClips } from './useHomeClips';
import { useHomeTimeline } from './useHomeTimeline';
import { useHomeHeaderScroll } from './useHomeHeaderScroll';
import { useHomeThumbnails } from './useHomeThumbnails';

const chips = homeFilters.map((key) => ({
  key,
  title: homeFilterStrings[key].title,
}));
export function HomeView() {
  return (
    <SafeAreaProvider style={styles.canvas}>
      <HomeContent />
    </SafeAreaProvider>
  );
}

function HomeContent() {
  const insets = useSafeAreaInsets();
  const [state, dispatch] = useReducer(reduce, undefined, () =>
    initialState(Date.now()),
  );
  const list = useRef<FlashListRef<HomeListItem>>(null);
  const [size, setSize] = useState({ width: 0, height: 0 });
  const [headerHeight, setHeaderHeight] = useState(0);
  const [contentHeight, setContentHeight] = useState(0);
  useHomeClips(dispatch);
  const dates = useMemo(
    () => state.clips.map((clip) => clip.createdAt),
    [state.clips],
  );
  const now = useHomeTimeline(dates, !state.isSearchVisible);
  useEffect(() => {
    dispatch({ type: 'timeChanged', now });
  }, [now]);
  const content = useMemo(
    () => makeHomeContent(state.clips, state.filter, state.now),
    [state.clips, state.filter, state.now],
  );
  const empty = useMemo(
    () =>
      homeEmptyState({
        loadPhase: state.loadPhase,
        clips: state.clips,
        content,
      }),
    [state.loadPhase, state.clips, content],
  );
  const items = useMemo(() => makeHomeListItems(content), [content]);
  const geometry = useMemo(
    () => ({
      headerHeight,
      safeTop: insets.top,
      // 상단 여백을 contentInset 대신 padding으로 줍니다. 스크롤 시작점은 0이므로 insetTop도 0입니다.
      insetTop: 0,
      insetBottom: insets.bottom,
      contentHeight,
      viewportHeight: size.height,
      sectionCount:
        empty === 'none'
          ? content.sections.length + Number(content.pinnedClips.length !== 0)
          : 0,
    }),
    [
      headerHeight,
      insets.top,
      insets.bottom,
      contentHeight,
      size.height,
      content,
      empty,
    ],
  );
  const header = useHomeHeaderScroll(list, geometry, items);
  const { reset } = header;
  const previousFilter = useRef(state.filter);
  useEffect(() => {
    if (previousFilter.current === state.filter) return;
    previousFilter.current = state.filter;
    reset();
  }, [state.filter, reset]);
  const columnWidth = homeColumnWidth(size.width);
  const scale = PixelRatio.get();
  const gridPixels = homeThumbnailPixels(columnWidth, scale);
  const pinnedPixels = homeThumbnailPixels(columnWidth, scale, true);
  const thumbnails = useHomeThumbnails(
    state,
    dispatch,
    gridPixels,
    pinnedPixels,
    0 < size.width,
  );
  useEffect(() => {
    list.current?.recomputeViewableItems();
  }, [items]);
  const thumbnail = (id: string, pixels: number) => ({
    thumbnailUri: state.thumbnails[`${id}:${pixels}`] ?? null,
    isThumbnailFailed: !!state.failedThumbnails[`${id}:${pixels}`],
  });
  const strings =
    empty === 'failed'
      ? {
          emptyTitle: '기록을 불러오지 못했습니다',
          emptyMessage: '앱을 다시 열어 기록을 확인해 주세요',
        }
      : homeFilterStrings[empty === 'empty' ? 'all' : state.filter];

  function renderItem({ item }: { item: HomeListItem }) {
    if (item.kind === 'pinned')
      return (
        <HomePinnedRow
          clips={item.clips.map((clip) => {
            const values = homeCardValues(clip, state.now, true);
            return {
              ...values,
              ...thumbnail(clip.id, pinnedPixels),
              id: clip.id,
              onSelect: () => openClip(clip.id, values.kind),
            };
          })}
          onViewableIdsChange={thumbnails.onViewableIdsChange}
        />
      );
    if (item.kind === 'section')
      return (
        <View
          style={[
            styles.section,
            item.hasPreviousSection && styles.nextSection,
          ]}
        >
          <SectionTitle title={homeSectionTitles[item.section]} />
        </View>
      );
    const values = homeCardValues(item.clip, state.now);
    return (
      <HomeGridCard onPress={() => openClip(item.clip.id, values.kind)}>
        {values.kind === 'text' ? (
          <ClipTextCard {...values} />
        ) : (
          <ClipImageCard {...values} {...thumbnail(item.clip.id, gridPixels)} />
        )}
      </HomeGridCard>
    );
  }

  return (
    <View style={styles.canvas}>
      <FlashList
        ref={list}
        data={items}
        renderItem={renderItem}
        extraData={state}
        masonry
        numColumns={2}
        CellRendererComponent={HomeListCell}
        keyExtractor={(item) => item.key}
        getItemType={(item) =>
          item.kind === 'card'
            ? item.clip.image === null
              ? 'text'
              : 'image'
            : item.kind
        }
        overrideItemLayout={(layout, item) => {
          layout.span = item.kind === 'card' ? 1 : 2;
        }}
        maintainVisibleContentPosition={{ disabled: true }}
        contentInsetAdjustmentBehavior="never"
        automaticallyAdjustsScrollIndicatorInsets={false}
        contentInset={{ top: 0, bottom: insets.bottom, left: 0, right: 0 }}
        contentContainerStyle={{
          paddingTop: headerHeight,
          paddingBottom: content.sections.length === 0 ? 0 : 10,
          minHeight: size.height + headerHeight,
        }}
        scrollEnabled={0 < geometry.sectionCount}
        showsVerticalScrollIndicator={0 < geometry.sectionCount}
        scrollsToTop={!state.isSearchVisible}
        alwaysBounceVertical
        scrollIndicatorInsets={{
          top: header.indicatorTop,
          bottom: insets.bottom,
        }}
        onLayout={({ nativeEvent: { layout } }) =>
          setSize({ width: layout.width, height: layout.height })
        }
        onContentSizeChange={(_, height) => setContentHeight(height)}
        scrollEventThrottle={16}
        onScroll={header.onScroll}
        onScrollBeginDrag={header.onScrollBeginDrag}
        onScrollEndDrag={header.onScrollEndDrag}
        onMomentumScrollBegin={header.onMomentumScrollBegin}
        onMomentumScrollEnd={header.onMomentumScrollEnd}
        viewabilityConfig={thumbnails.viewabilityConfig}
        onViewableItemsChanged={thumbnails.onViewableItemsChanged}
      />
      {empty !== 'none' && (
        <View
          pointerEvents="none"
          style={[styles.empty, { top: headerHeight, bottom: insets.bottom }]}
        >
          <View style={styles.emptyContent}>
            <HomeEmptyState
              emptyTitle={strings.emptyTitle}
              emptyBody={strings.emptyMessage}
            />
          </View>
        </View>
      )}
      <Animated.View
        onLayout={({ nativeEvent: { layout } }) =>
          setHeaderHeight(layout.height)
        }
        style={[
          styles.header,
          {
            paddingTop: insets.top,
            transform: [{ translateY: header.translateY }],
          },
        ]}
      >
        <HomeTitleHeader
          onSearchButtonPress={openSearch}
          isSearchButtonHidden={state.isSearchVisible}
        />
        <View style={styles.filters}>
          <HomeFilterBar
            chips={chips}
            selectedKey={state.filter}
            onSelect={(filter) => dispatch({ type: 'filterSelected', filter })}
          />
        </View>
      </Animated.View>
      <EdgeFade height={insets.top} />
    </View>
  );
}

const styles = StyleSheet.create({
  canvas: { flex: 1, backgroundColor: colors.Canvas },
  header: {
    position: 'absolute',
    top: 0,
    left: 0,
    right: 0,
    backgroundColor: colors.Canvas,
    paddingBottom: 4,
  },
  filters: { marginTop: -4 },
  section: { height: 44 },
  nextSection: { height: 54, paddingTop: 10 },
  empty: {
    position: 'absolute',
    left: 40,
    right: 40,
    justifyContent: 'center',
    alignItems: 'center',
  },
  emptyContent: { transform: [{ translateY: 24 }] },
});
