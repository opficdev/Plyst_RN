import {
  useDeferredValue,
  useEffect,
  useMemo,
  useLayoutEffect,
  useRef,
  useState,
} from 'react';
import {
  Animated,
  Easing,
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
import { searchActions as actions } from './actions';
import {
  ScreenProvider,
  useScreenState,
  useScreenDispatch,
} from '../../Shared/State/screenStore';
import { useClipThumbnails } from '../ClipGrid/useThumbnails';
import { useClipTimeline } from '../ClipGrid/useTimeline';

let hasPresentedKeyboard = false;
const AnimatedPressable = Animated.createAnimatedComponent(Pressable);

type SearchListItem =
  | { kind: 'header'; key: string }
  | { kind: 'card'; key: string; clip: ClipRecord };
const chips = clipFilters.map((key) => ({
  key,
  title: clipFilterTitles[key],
}));

export type SearchViewProps = {
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
  const [progress] = useState(() => new Animated.Value(0));
  const hasEntered = useRef(false);
  const hasStarted = useRef(false);
  const openTimer = useRef<ReturnType<typeof setTimeout> | null>(null);
  const isClosing = useRef(false);
  const isMounted = useRef(false);
  const animation = useRef<Animated.CompositeAnimation | null>(null);
  const [listWidth, setListWidth] = useState(0);
  const dates = useMemo(
    () => state.clips.map((clip) => clip.createdAt),
    [state.clips],
  );
  const now = useClipTimeline(dates, true);
  useEffect(() => {
    dispatch({ type: 'timeChanged', now });
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
      animation.current?.stop();
      if (openTimer.current !== null) clearTimeout(openTimer.current);
    };
  }, [progress]);

  // 앱을 켠 뒤 처음 키보드를 띄울 때는 메인 스레드를 막아 페이드가 한 프레임에 끝나므로 페이드 뒤에 포커스를 준다.
  // 그 뒤로는 원본처럼 페이드와 동시에 포커스를 준다. 시작 신호는 돋보기 이미지가 화면에 그려진 뒤에 온다.
  function startOpen() {
    if (hasStarted.current || !isMounted.current || isClosing.current) return;
    hasStarted.current = true;
    animation.current = Animated.timing(progress, {
      toValue: 1,
      duration: 300,
      easing: Easing.bezier(0.42, 0, 0.58, 1),
      useNativeDriver: false,
    });
    if (hasPresentedKeyboard) {
      animation.current.start();
      hasPresentedKeyboard = true;
      input.current?.focus();
    } else {
      animation.current.start(({ finished }) => {
        if (finished && isMounted.current && !isClosing.current) {
          hasPresentedKeyboard = true;
          input.current?.focus();
        }
      });
    }
  }

  function enter() {
    if (hasEntered.current) return;
    hasEntered.current = true;
    openTimer.current = setTimeout(startOpen, 800);
  }

  function close() {
    if (isClosing.current) return;
    isClosing.current = true;
    input.current?.blur();
    animation.current?.stop();
    animation.current = Animated.timing(progress, {
      toValue: 0,
      duration: 300,
      easing: Easing.bezier(0.42, 0, 0.58, 1),
      useNativeDriver: false,
    });
    animation.current.start(({ finished }) => {
      if (finished && isMounted.current) navigation.closeSearch();
    });
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
      <Animated.View
        pointerEvents="none"
        style={[styles.backdrop, { opacity: progress }]}
      />
      <View style={{ height: insets.top + 48 }}>
        <Animated.View
          style={[
            styles.searchBar,
            {
              top: insets.top - 5,
              opacity: progress,
              width: progress.interpolate({
                inputRange: [0, 1],
                outputRange: [0, Math.max(0, width - 96)],
              }),
            },
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
            onChangeText={(value) =>
              dispatch({ type: 'queryChanged', query: value })
            }
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
        </Animated.View>
        <AnimatedPressable
          style={[styles.cancel, { top: insets.top - 5, opacity: progress }]}
          onPress={close}
        >
          <Animated.View
            style={[
              styles.buttonIcon,
              {
                opacity: progress.interpolate({
                  inputRange: [0, 1],
                  outputRange: [1, 0],
                }),
              },
            ]}
          >
            <Image source="sf:magnifyingglass" style={styles.cancelIcon} />
          </Animated.View>
          <Animated.View style={[styles.buttonIcon, { opacity: progress }]}>
            <Image
              source="sf:xmark"
              contentFit="none"
              style={styles.xmarkIcon}
            />
          </Animated.View>
        </AnimatedPressable>
      </View>
      <KeyboardAvoidingView
        behavior="padding"
        style={[styles.root, { marginBottom: insets.bottom }]}
      >
        <Animated.View style={[styles.root, { opacity: progress }]}>
          <View style={styles.filters}>
            <HomeFilterBar
              keyboardShouldPersistTaps="handled"
              chips={chips}
              selectedKey={state.filter}
              onSelect={(filter) =>
                dispatch({ type: 'filterSelected', filter })
              }
            />
          </View>
          <View style={styles.list}>
            {mode === 'recent' ? (
              <SearchRecent
                {...recent}
                onTermButtonPress={(term) =>
                  dispatch({ type: 'queryChanged', query: term })
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
        </Animated.View>
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
  return (
    <View>
      <View style={styles.recentHeader}>
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
            contentContainerStyle={styles.chips}
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
  message: { marginHorizontal: 20, fontSize: 14, color: colors.SecondaryText },
  hint: {
    marginTop: 42,
    marginHorizontal: 20,
    fontSize: 13,
    color: colors.SecondaryText,
  },
});
