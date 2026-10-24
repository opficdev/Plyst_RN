import {
  useDeferredValue,
  useEffect,
  useMemo,
  useLayoutEffect,
  useRef,
  useState,
} from 'react';
import {
  Keyboard,
  KeyboardAvoidingView,
  PixelRatio,
  Pressable,
  ScrollView,
  StyleSheet,
  Text,
  TextInput,
  View,
  useWindowDimensions,
} from 'react-native';
import { Image } from 'expo-image';
import {
  SafeAreaProvider,
  useSafeAreaInsets,
} from 'react-native-safe-area-context';
import { FlashList } from '@shopify/flash-list';
import type { FlashListRef } from '@shopify/flash-list';
import type { ClipKind, ClipRecord } from '../../Model/clipRecord';
import {
  ClipImageCard,
  ClipTextCard,
  HomeEmptyState,
  HomeFilterBar,
  SearchTermChip,
  SectionTitle,
} from '../../Shared/UI';
import { colors, typography } from '../../Shared/Theme';
import { ClipGridCard, ClipListCell } from '../ClipGrid/Card';
import {
  clipCardValues,
  clipColumnWidth,
  clipListRightMargin,
  clipThumbnailPixels,
} from '../ClipGrid/cardValues';
import { clipFilters, clipFilterTitles } from '../ClipGrid/filter';
import { searchCardText } from './cardText';
import {
  createSearchTimeTexts,
  makeSearchContent,
  searchEmptyStrings,
  searchHeaderTitle,
  searchMode,
  searchRecentDisplay,
} from './content';
import { createSearchIndex } from './match';
import type { SearchState } from './state';
import { createSearchStore } from './store';
import { searchActions as actions } from './state';
import {
  ScreenProvider,
  useScreenState,
  useScreenDispatch,
} from '../../Shared/State/screenStore';
import { useClipThumbnails } from '../ClipGrid/useThumbnails';
import { useClipTimeline } from '../ClipGrid/useTimeline';
import { NavigationBarButton } from './NavigationBarButton';
import { SearchTransition } from './Transition';

let hasPresentedKeyboard = false;

type SearchListItem =
  | { kind: 'header'; key: string }
  | { kind: 'card'; key: string; clip: ClipRecord };
const chips = clipFilters.map((key) => ({
  key,
  title: clipFilterTitles[key],
}));

export type SearchViewProps = {
  // iPhone Duo이면 true이며 닫기 버튼은 시스템 헤더 항목이 맡으므로 RN 취소 버튼을 그리지 않음
  usesSystemBar: boolean;
  navigation: {
    openClip: (id: string, kind: ClipKind) => void;
    closeSearch: () => void;
  };
};

export function SearchView(props: SearchViewProps) {
  return (
    <SafeAreaProvider style={styles.root}>
      <SearchRoot {...props} />
    </SafeAreaProvider>
  );
}

function SearchRoot(props: SearchViewProps) {
  const [index] = useState(createSearchIndex);
  const [times] = useState(createSearchTimeTexts);
  const [screen] = useState(() => createSearchStore(index.cancelPrebuild));
  useLayoutEffect(() => {
    screen.start();
    return () => screen.dispose();
  }, [screen]);
  useEffect(() => {
    screen.store.dispatch(actions.viewDidLoad());
  }, [screen]);
  return (
    <ScreenProvider store={screen.store}>
      <SearchScreen index={index} times={times} {...props} />
    </ScreenProvider>
  );
}

function SearchScreen({
  index,
  times,
  usesSystemBar,
  navigation,
}: SearchViewProps & {
  index: ReturnType<typeof createSearchIndex>;
  times: ReturnType<typeof createSearchTimeTexts>;
}) {
  const insets = useSafeAreaInsets();
  const { width } = useWindowDimensions();
  const state = useScreenState<SearchState>();
  const dispatch = useScreenDispatch();
  const input = useRef<TextInput>(null);
  const list = useRef<FlashListRef<SearchListItem>>(null);
  const [isPresented, setIsPresented] = useState(false);
  const hasEntered = useRef(false);
  const hasStarted = useRef(false);
  const openTimer = useRef<ReturnType<typeof setTimeout> | null>(null);
  const closeTimer = useRef<ReturnType<typeof setTimeout> | null>(null);
  const isClosing = useRef(false);
  const isMounted = useRef(false);
  const isFocusPending = useRef(false);
  const [listWidth, setListWidth] = useState(0);
  const dates = useMemo(
    () => state.clips.map((clip) => clip.createdAt),
    [state.clips],
  );
  const now = useClipTimeline(dates, true);
  useEffect(() => {
    dispatch(actions.timeChanged(now));
  }, [dispatch, now]);
  useEffect(() => {
    times.retain(state.clips);
    return index.prebuild(state.clips);
  }, [index, times, state.clips]);
  useEffect(() => () => index.dispose(), [index]);
  useEffect(() => {
    isMounted.current = true;
    return () => {
      isMounted.current = false;
      if (openTimer.current !== null) clearTimeout(openTimer.current);
      if (closeTimer.current !== null) clearTimeout(closeTimer.current);
    };
  }, []);

  // 페이드와 서치바 확장은 PlystSearchTransition이 렌더 서버에서 0.3초 동안 움직임
  // 앱을 켠 뒤 처음 키보드를 띄울 때는 메인 스레드를 막으므로 서치바 확장이 끝난 뒤에 포커스를 줌
  // 그 뒤로는 원본처럼 확장과 동시에 포커스를 줌
  // 시작 신호는 돋보기 이미지가 화면에 그려진 뒤에 옴
  function startOpen() {
    if (hasStarted.current || !isMounted.current || isClosing.current) return;
    hasStarted.current = true;
    setIsPresented(true);
    if (hasPresentedKeyboard) {
      input.current?.focus();
    } else {
      isFocusPending.current = true;
    }
  }

  function enter() {
    if (hasEntered.current) return;
    hasEntered.current = true;
    openTimer.current = setTimeout(startOpen, 800);
  }

  function finishClose() {
    if (!isMounted.current) return;
    if (closeTimer.current !== null) clearTimeout(closeTimer.current);
    closeTimer.current = null;
    navigation.closeSearch();
  }

  // 닫기 애니메이션 완료 신호가 오지 않아도 닫히도록 대체 타이머를 둠
  function close() {
    if (isClosing.current) return;
    isClosing.current = true;
    input.current?.blur();
    if (!hasStarted.current) {
      finishClose();
      return;
    }
    setIsPresented(false);
    closeTimer.current = setTimeout(finishClose, 800);
  }

  function transitionEnded(didPresent: boolean) {
    if (!isMounted.current) return;
    if (!didPresent) {
      finishClose();
      return;
    }
    if (isFocusPending.current && !isClosing.current) {
      isFocusPending.current = false;
      hasPresentedKeyboard = true;
      input.current?.focus();
    }
  }

  const query = useDeferredValue(state.query);
  const content = useMemo(
    () =>
      makeSearchContent(
        state.clips,
        query,
        state.filter,
        state.now,
        index,
        times,
      ),
    [state.clips, query, state.filter, state.now, index, times],
  );
  const mode = searchMode(content, state.loadPhase, state.clips);
  const items = useMemo<SearchListItem[]>(
    () =>
      content.results.length === 0
        ? []
        : [
            { kind: 'header', key: 'header' },
            ...content.results.map((clip) => ({
              kind: 'card' as const,
              key: clip.id,
              clip,
            })),
          ],
    [content],
  );
  const previousFilter = useRef(state.filter);
  useEffect(() => {
    if (previousFilter.current === state.filter) return;
    previousFilter.current = state.filter;
    list.current?.scrollToOffset({ offset: 0, animated: true });
  }, [state.filter]);
  const pixels = clipThumbnailPixels(
    clipColumnWidth(listWidth),
    PixelRatio.get(),
  );
  const thumbnails = useClipThumbnails<SearchListItem>(
    state,
    dispatch,
    actions,
    pixels,
    pixels,
    0 < listWidth && mode === 'results',
  );
  useEffect(() => {
    list.current?.recomputeViewableItems();
  }, [items, mode]);

  function copy(clip: ClipRecord) {
    dispatch(actions.copy(clip.id));
  }

  function renderItem({ item }: { item: SearchListItem }) {
    if (item.kind === 'header')
      return (
        <View style={styles.resultHeader}>
          <SectionTitle title={searchHeaderTitle(content)} />
        </View>
      );
    const values = clipCardValues(item.clip, state.now);
    const text = searchCardText(item.clip, content.query, index);
    return (
      <ClipGridCard
        onPress={() => {
          Keyboard.dismiss();
          navigation.openClip(item.clip.id, values.kind);
        }}
      >
        {values.kind === 'text' ? (
          <ClipTextCard
            {...values}
            {...text}
            onCopyButtonPress={() => void copy(item.clip)}
          />
        ) : (
          <ClipImageCard
            {...values}
            nameHighlights={text.nameHighlights}
            thumbnailUri={state.thumbnails[`${item.clip.id}:${pixels}`] ?? null}
            isThumbnailFailed={
              !!state.failedThumbnails[`${item.clip.id}:${pixels}`]
            }
            onCopyButtonPress={() => void copy(item.clip)}
          />
        )}
      </ClipGridCard>
    );
  }
  const empty = searchEmptyStrings(
    content.query,
    state.filter,
    mode === 'failed',
  );
  const recent = searchRecentDisplay(
    state.searchHistoryPhase,
    state.searchHistory,
  );

  return (
    <View style={styles.root} onLayout={enter}>
      <SearchTransition
        effect="fadeIn"
        isPresented={isPresented}
        pointerEvents="none"
        style={styles.backdrop}
      />
      <View style={{ height: insets.top + 48 }}>
        <SearchTransition
          effect="expand"
          isPresented={isPresented}
          onTransitionEnd={transitionEnded}
          style={[
            styles.searchBar,
            { top: insets.top - 5, width: Math.max(0, width - 96) },
          ]}
        >
          <Image
            source="sf:magnifyingglass"
            contentFit="contain"
            style={styles.searchIcon}
            onDisplay={startOpen}
            onLoad={startOpen}
          />
          <TextInput
            ref={input}
            value={state.query}
            onChangeText={(value) => dispatch(actions.queryChanged(value))}
            placeholder="복사한 내용 검색"
            placeholderTextColor={colors.SecondaryText}
            returnKeyType="search"
            clearButtonMode="while-editing"
            autoCorrect={false}
            spellCheck={false}
            autoCapitalize="none"
            allowFontScaling={false}
            style={styles.input}
            onSubmitEditing={() => {
              dispatch(actions.submitQuery());
              input.current?.blur();
            }}
          />
        </SearchTransition>
        {usesSystemBar ? (
          <NavigationBarButton side="right" icon="xmark" onPress={close} />
        ) : (
          <SearchTransition
            effect="fadeIn"
            isPresented={isPresented}
            style={[styles.cancel, { top: insets.top - 5 }]}
          >
            <Pressable style={styles.cancelPress} onPress={close}>
              <SearchTransition
                effect="fadeOut"
                isPresented={isPresented}
                style={styles.buttonIcon}
              >
                <Image source="sf:magnifyingglass" style={styles.cancelIcon} />
              </SearchTransition>
              <SearchTransition
                effect="fadeIn"
                isPresented={isPresented}
                style={styles.buttonIcon}
              >
                <Image
                  source="sf:xmark"
                  contentFit="none"
                  style={styles.xmarkIcon}
                />
              </SearchTransition>
            </Pressable>
          </SearchTransition>
        )}
      </View>
      <KeyboardAvoidingView
        behavior="padding"
        style={[styles.root, { marginBottom: insets.bottom }]}
      >
        <SearchTransition
          effect="fadeIn"
          isPresented={isPresented}
          style={styles.root}
        >
          <View style={styles.filters}>
            <HomeFilterBar
              keyboardShouldPersistTaps="handled"
              chips={chips}
              selectedKey={state.filter}
              onSelect={(filter) => dispatch(actions.filterSelected(filter))}
            />
          </View>
          {/* iPhone Duo는 오른쪽 safe area에 바 항목이 놓이므로 카드와 구분선을 safe area 경계에서 끝냄 */}
          <View
            style={[
              styles.list,
              { marginRight: clipListRightMargin(insets.right) },
            ]}
          >
            {mode === 'recent' ? (
              <SearchRecent
                {...recent}
                onTermButtonPress={(term) =>
                  dispatch(actions.queryChanged(term))
                }
                onRemoveButtonPress={(term) =>
                  dispatch(actions.removeRecentTerm(term))
                }
                onClearButtonPress={() => dispatch(actions.clearRecentTerms())}
              />
            ) : mode === 'empty' || mode === 'failed' ? (
              <View style={styles.empty}>
                <HomeEmptyState
                  emptyTitle={empty.title}
                  emptyBody={empty.message}
                />
              </View>
            ) : (
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
                scrollIndicatorInsets={{
                  right: insets.right - clipListRightMargin(insets.right),
                }}
                contentContainerStyle={{ paddingBottom: 16 }}
                keyboardDismissMode="on-drag"
                keyboardShouldPersistTaps="handled"
                onLayout={({ nativeEvent: { layout } }) =>
                  setListWidth(layout.width)
                }
                viewabilityConfig={thumbnails.viewabilityConfig}
                onViewableItemsChanged={thumbnails.onViewableItemsChanged}
              />
            )}
          </View>
        </SearchTransition>
      </KeyboardAvoidingView>
    </View>
  );
}

function SearchRecent({
  terms,
  message,
  isClearVisible,
  onTermButtonPress,
  onRemoveButtonPress,
  onClearButtonPress,
}: ReturnType<typeof searchRecentDisplay> & {
  onTermButtonPress: (term: string) => void;
  onRemoveButtonPress: (term: string) => void;
  onClearButtonPress: () => void;
}) {
  // 본문 틀이 safe area 안으로 16 들어오면 오른쪽 여백을 16으로 줄여 구분선과 칩을 safe area 경계에서 끝냄
  const isRightInset = 0 < useSafeAreaInsets().right;
  return (
    <View>
      <View
        style={[styles.recentHeader, isRightInset && styles.insetRecentHeader]}
      >
        <Text allowFontScaling={false} style={styles.recentTitle}>
          최근 검색어
        </Text>
        <View style={styles.rule} />
        {isClearVisible && (
          <Pressable onPress={onClearButtonPress}>
            <Text allowFontScaling={false} style={styles.clear}>
              지우기
            </Text>
          </Pressable>
        )}
      </View>
      <View style={styles.recentTerms}>
        {terms.length !== 0 ? (
          <ScrollView
            horizontal
            keyboardShouldPersistTaps="handled"
            showsHorizontalScrollIndicator={false}
            style={isRightInset && styles.insetChipScroll}
            contentContainerStyle={[
              styles.chips,
              isRightInset && styles.insetChips,
            ]}
          >
            {terms.map((term) => (
              <SearchTermChip
                key={term}
                term={term}
                onTermButtonPress={() => onTermButtonPress(term)}
                onRemoveButtonPress={() => onRemoveButtonPress(term)}
              />
            ))}
          </ScrollView>
        ) : (
          <Text allowFontScaling={false} style={styles.message}>
            {message}
          </Text>
        )}
      </View>
      <Text allowFontScaling={false} style={styles.hint}>
        텍스트는 내용과 이름으로, 이미지는 이름과 저장 시각으로 찾을 수 있어요.
      </Text>
    </View>
  );
}

const styles = StyleSheet.create({
  root: { flex: 1 },
  backdrop: {
    ...StyleSheet.absoluteFill,
    backgroundColor: colors.Canvas,
  },
  searchBar: {
    position: 'absolute',
    right: 76,
    height: 44,
    borderRadius: 22,
    borderWidth: 1,
    borderColor: colors.Outline,
    backgroundColor: colors.Card,
    overflow: 'hidden',
    flexDirection: 'row',
    alignItems: 'center',
  },
  searchIcon: {
    marginLeft: 13,
    width: 18,
    height: 18,
    color: colors.SecondaryText,
  },
  input: {
    flex: 1,
    marginLeft: 10,
    marginRight: 11,
    height: 44,
    padding: 0,
    fontSize: 16,
    color: colors.PrimaryText,
  },
  cancel: {
    position: 'absolute',
    right: 20,
    width: 44,
    height: 44,
    borderRadius: 22,
    borderWidth: 1,
    borderColor: colors.Outline,
    backgroundColor: colors.Card,
    overflow: 'hidden',
    alignItems: 'center',
    justifyContent: 'center',
  },
  cancelPress: {
    width: 44,
    height: 44,
    alignItems: 'center',
    justifyContent: 'center',
  },
  buttonIcon: { position: 'absolute' },
  cancelIcon: {
    width: 28,
    height: 28,
    fontSize: 17,
    fontWeight: '600',
    color: colors.PrimaryText,
  },
  xmarkIcon: {
    width: 23,
    height: 21.6667,
    fontSize: 17,
    fontWeight: '600',
    color: colors.PrimaryText,
  },
  filters: { height: 40 },
  list: { flex: 1, marginTop: 4 },
  resultHeader: { height: 44 },
  empty: {
    flex: 1,
    marginHorizontal: 40,
    alignItems: 'center',
    justifyContent: 'center',
  },
  recentHeader: {
    marginTop: 20,
    marginHorizontal: 20,
    flexDirection: 'row',
    alignItems: 'center',
    gap: 10,
  },
  recentTitle: {
    ...typography.sectionLabel,
    letterSpacing: 0,
    color: colors.SecondaryText,
  },
  rule: { flex: 1, height: 1, backgroundColor: colors.Outline },
  clear: { ...typography.label, color: colors.SecondaryText },
  recentTerms: { height: 36, marginTop: 14 },
  chips: { paddingHorizontal: 20, gap: 8, alignItems: 'center' },
  insetRecentHeader: { marginRight: 16 },
  insetChipScroll: { marginRight: 16 },
  insetChips: { paddingRight: 0 },
  message: { marginHorizontal: 20, fontSize: 14, color: colors.SecondaryText },
  hint: {
    marginTop: 42,
    marginHorizontal: 20,
    fontSize: 13,
    color: colors.SecondaryText,
  },
});
