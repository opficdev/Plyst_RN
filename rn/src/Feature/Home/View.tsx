import { useLayoutEffect, useEffect, useMemo, useRef, useState } from 'react';
import { Animated, PixelRatio, StyleSheet, View } from 'react-native';
import {
  SafeAreaProvider,
  useSafeAreaInsets,
} from 'react-native-safe-area-context';
import { FlashList } from '@shopify/flash-list';
import type { FlashListRef } from '@shopify/flash-list';
import { openClip, openSearch } from 'plyst-bridge';
import type { ClipRecord } from '../../Model/clipRecord';
import {
  ActionSheet,
  HomeSaveBar,
  ClipTextCard,
  ClipImageCard,
  EdgeFade,
  HomeEmptyState,
  HomeFilterBar,
  HomePinnedRow,
  HomeTitleHeader,
  SectionTitle,
} from '../../Shared/UI';
import { homeMenuTitle, homeMenuSummary } from './menu';
import { colors, spacing } from '../../Shared/Theme';
import { ClipGridCard, ClipListCell } from '../ClipGrid/Card';
import { homeEmptyState, homeFilterStrings, makeHomeContent } from './content';
import { clipFilters, clipFilterTitles } from '../ClipGrid/filter';
import { clipSectionTitles } from '../ClipGrid/section';
import {
  clipCardValues,
  clipColumnWidth,
  clipThumbnailPixels,
} from '../ClipGrid/cardValues';
import { makeHomeListItems } from './listItems';
import type { HomeListItem } from './listItems';
import type { HomeState } from './state';
import { createHomeStore } from './store';
import { homeActions as actions } from './actions';
import {
  ScreenProvider,
  useScreenState,
  useScreenDispatch,
} from '../../Shared/State/screenStore';
import { useClipTimeline } from '../ClipGrid/useTimeline';
import { useHomeHeaderScroll } from './useHeaderScroll';
import { useClipThumbnails } from '../ClipGrid/useThumbnails';

const chips = clipFilters.map((key) => ({
  key,
  title: clipFilterTitles[key],
}));
export function HomeView() {
  return (
    <SafeAreaProvider style={styles.canvas}>
      <HomeRoot />
    </SafeAreaProvider>
  );
}

function HomeRoot() {
  const [screen] = useState(createHomeStore);
  useLayoutEffect(() => {
    screen.start();
    return () => screen.dispose();
  }, [screen]);
  useEffect(() => {
    screen.store.dispatch(actions.viewDidLoad());
  }, [screen]);
  return (
    <ScreenProvider store={screen.store}>
      <HomeContent getState={screen.store.getState} />
    </ScreenProvider>
  );
}

function HomeContent({ getState }: { getState: () => HomeState }) {
  const insets = useSafeAreaInsets();
  const state = useScreenState<HomeState>();
  const dispatch = useScreenDispatch();

  function selectClip(clip: ClipRecord) {
    const current = getState();
    if (current.isMenuVisible || current.isDeleteConfirmVisible) return;
    openClip(clip.id, clip.image === null ? 'text' : 'image');
  }
  function showMenu(clip: ClipRecord) {
    const current = getState();
    if (current.isMenuVisible || current.isDeleteConfirmVisible) return;
    dispatch({ type: 'menuShown', clip });
  }
  function copy(clip: ClipRecord) {
    dispatch(actions.copy(clip.id));
  }
  const save = () => dispatch(actions.saveCurrentClipboard());
  const togglePin = () => dispatch(actions.setPinned());
  const deleteClip = () => dispatch(actions.delete());
  function confirmDelete() {
    const current = getState();
    const clip = current.clips.find((clip) => clip.id === current.menuClip?.id);
    if (clip) dispatch({ type: 'deleteConfirmShown', clip });
  }

  const list = useRef<FlashListRef<HomeListItem>>(null);
  const [size, setSize] = useState({ width: 0, height: 0 });
  const [headerHeight, setHeaderHeight] = useState(0);
  const [contentHeight, setContentHeight] = useState(0);
  const dates = useMemo(
    () => state.clips.map((clip) => clip.createdAt),
    [state.clips],
  );
  const now = useClipTimeline(dates, !state.isSearchVisible);
  useEffect(() => {
    dispatch({ type: 'timeChanged', now });
  }, [dispatch, now]);
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
      insetBottom: 0,
      contentHeight,
      viewportHeight: size.height,
      sectionCount:
        empty === 'none'
          ? content.sections.length + Number(content.pinnedClips.length !== 0)
          : 0,
    }),
    [headerHeight, insets.top, contentHeight, size.height, content, empty],
  );
  const header = useHomeHeaderScroll(list, geometry, items);
  const { reset } = header;
  const previousFilter = useRef(state.filter);
  useEffect(() => {
    if (previousFilter.current === state.filter) return;
    previousFilter.current = state.filter;
    reset();
  }, [state.filter, reset]);
  const columnWidth = clipColumnWidth(size.width);
  const scale = PixelRatio.get();
  const gridPixels = clipThumbnailPixels(columnWidth, scale);
  const pinnedPixels = clipThumbnailPixels(columnWidth, scale, true);
  const thumbnails = useClipThumbnails<HomeListItem>(
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
            const values = clipCardValues(clip, state.now, true);
            return {
              ...values,
              ...thumbnail(clip.id, pinnedPixels),
              id: clip.id,
              onSelect: () => selectClip(clip),
              onShowMenu: () => showMenu(clip),
              onCopyButtonPress: () => void copy(clip),
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
          <SectionTitle title={clipSectionTitles[item.section]} />
        </View>
      );
    const values = clipCardValues(item.clip, state.now);
    return (
      <ClipGridCard
        onPress={() => selectClip(item.clip)}
        onShowMenu={() => showMenu(item.clip)}
      >
        {values.kind === 'text' ? (
          <ClipTextCard
            {...values}
            onCopyButtonPress={() => void copy(item.clip)}
            onCopyButtonLongPress={() => showMenu(item.clip)}
          />
        ) : (
          <ClipImageCard
            {...values}
            {...thumbnail(item.clip.id, gridPixels)}
            onCopyButtonPress={() => void copy(item.clip)}
            onCopyButtonLongPress={() => showMenu(item.clip)}
          />
        )}
      </ClipGridCard>
    );
  }

  return (
    <View style={styles.canvas}>
      <View style={styles.list}>
        <FlashList
          ref={list}
          data={items}
          renderItem={renderItem}
          extraData={state}
          masonry
          numColumns={2}
          CellRendererComponent={ClipListCell}
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
          contentInset={{ top: 0, bottom: 0, left: 0, right: 0 }}
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
            bottom: 0,
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
            style={[styles.empty, { top: headerHeight, bottom: 0 }]}
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
            isSearchButtonDisabled={state.isSearchVisible}
          />
          <View style={styles.filters}>
            <HomeFilterBar
              chips={chips}
              selectedKey={state.filter}
              onSelect={(filter) =>
                dispatch({ type: 'filterSelected', filter })
              }
            />
          </View>
        </Animated.View>
        <EdgeFade height={insets.top} />
      </View>
      <View style={{ paddingBottom: insets.bottom + spacing.card }}>
        <HomeSaveBar
          isSaving={state.isSaving}
          onSaveButtonPress={() => void save()}
        />
      </View>
      <ActionSheet
        isVisible={state.isMenuVisible}
        title={state.menuClip ? homeMenuTitle(state.menuClip) : '텍스트'}
        message={
          state.menuClip ? homeMenuSummary(state.menuClip) : '이름 없는 이미지'
        }
        onClose={() => dispatch({ type: 'menuClosed' })}
        items={[
          {
            title:
              (state.menuClip?.pinnedAt ?? null) !== null
                ? '고정 해제'
                : '고정',
            role: 'default',
            handler: () => void togglePin(),
          },
          { title: '삭제', role: 'destructive', handler: confirmDelete },
          { title: '취소', role: 'cancel' },
        ]}
      />
      <ActionSheet
        isVisible={state.isDeleteConfirmVisible}
        title={`이 ${state.menuClip ? homeMenuTitle(state.menuClip) : '텍스트'}를 삭제할까요?`}
        message="삭제하면 되돌릴 수 없습니다."
        onClose={() => dispatch({ type: 'deleteConfirmClosed' })}
        items={[
          {
            title: '삭제',
            role: 'destructive',
            handler: () => void deleteClip(),
          },
          { title: '취소', role: 'cancel' },
        ]}
      />
    </View>
  );
}

const styles = StyleSheet.create({
  list: { flex: 1, marginBottom: spacing.card },
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
