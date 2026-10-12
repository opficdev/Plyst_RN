import { useEffect, useLayoutEffect, useRef, useState } from 'react';
import { Image } from 'expo-image';
import {
  ActivityIndicator,
  Pressable,
  ScrollView,
  useWindowDimensions,
  StyleSheet,
  Switch,
  Text,
  TextInput,
  View,
} from 'react-native';
import {
  SafeAreaProvider,
  useSafeAreaInsets,
} from 'react-native-safe-area-context';
import { closeScreen, setSaveEnabled } from 'plyst-bridge';
import { ActionSheet } from '../../Shared/UI';
import {
  ClipDetailActionBar,
  ClipDetailDates,
} from '../../Shared/UI/ClipDetail';
import { colors, radius, spacing, typography } from '../../Shared/Theme';
import { formatClipDate } from '../ClipDetail/formatClipDate';
import { canSave } from './imageDetailDraft';
import type { ImageDetailState } from './imageDetailDraft';
import { useScrollFieldIntoView } from '../ClipDetail/useScrollFieldIntoView';

import {
  ScreenProvider,
  useScreenState,
  useScreenDispatch,
} from '../../Shared/State/screenStore';
import { createImageDetailStore } from './store';
import type { ImageDetailStoreState } from './store';
import { imageDetailActions as actions } from './actions';

type ImageDetailViewProps = { clipID: string };

export function ImageDetailView({ clipID }: ImageDetailViewProps) {
  return (
    <SafeAreaProvider style={styles.canvas}>
      <ImageDetailRoot key={clipID} clipID={clipID} />
    </SafeAreaProvider>
  );
}

function ImageDetailRoot({ clipID }: ImageDetailViewProps) {
  const [screen] = useState(() => createImageDetailStore(clipID));
  useLayoutEffect(() => {
    screen.start();
    return () => screen.dispose();
  }, [screen]);
  useEffect(() => {
    screen.store.dispatch(actions.viewDidLoad());
  }, [screen]);
  return (
    <ScreenProvider store={screen.store}>
      <ImageDetailContent />
    </ScreenProvider>
  );
}

function ImageDetailContent() {
  const state = useScreenState<ImageDetailStoreState>();
  const didClose = useRef(false);
  const isClosed = state === 'closed' || !!(state?.isRemoved || state?.isSaved);
  useEffect(() => {
    if (didClose.current || !isClosed) return;
    didClose.current = true;
    closeScreen();
  }, [isClosed]);
  if (state === 'closed') return null;
  if (state === null) return <View style={styles.canvas} />;
  return <ImageDetailEditor state={state} />;
}

function ImageDetailEditor({ state }: { state: ImageDetailState }) {
  const dispatch = useScreenDispatch();
  const [previewWidth, setPreviewWidth] = useState(0);
  const window = useWindowDimensions();
  const insets = useSafeAreaInsets();
  const { contentRef, nameRef, nameInputProps, scrollProps } =
    useScrollFieldIntoView();
  const isSaveEnabled = canSave(state);

  useEffect(() => {
    setSaveEnabled(isSaveEnabled);
  }, [isSaveEnabled]);

  function showDeleteSheet() {
    if (state.isDeleting || state.isRemoved || state.isDeleteSheetOpen) return;
    dispatch({ type: 'deleteSheetShown' });
  }
  const copy = () => dispatch(actions.copy());
  const startDelete = () => dispatch(actions.delete());
  const saveToPhotos = () => dispatch(actions.saveToPhotos());

  const { clip, draft, preview } = state;
  const image = clip.image;
  const previewHeight = Math.min(
    Math.max(96, previewWidth / preview.aspectRatio),
    Math.max(0, window.height - insets.top - insets.bottom) * 0.6,
  );
  const photoDisabled = state.isDeleting || state.isSavingToPhotos;
  return (
    <View style={styles.canvas}>
      <ScrollView
        style={styles.scroll}
        {...scrollProps}
        contentInsetAdjustmentBehavior="never"
      >
        <View ref={contentRef} style={styles.content} collapsable={false}>
          <View style={styles.card}>
            <Text allowFontScaling={false} style={styles.meta}>
              {image &&
                `${image.pixelWidth} × ${image.pixelHeight} px, ${image.byteCountText}`}
            </Text>
            <View
              style={[styles.preview, { height: previewHeight }]}
              onLayout={(event) =>
                setPreviewWidth(event.nativeEvent.layout.width)
              }
            >
              {preview.uri !== null && (
                <Image
                  source={{ uri: preview.uri }}
                  style={StyleSheet.absoluteFill}
                  cachePolicy="none"
                  contentFit="contain"
                  onLoad={({ source }) =>
                    dispatch({
                      type: 'previewLoaded',
                      width: source.width,
                      height: source.height,
                    })
                  }
                  onError={() => dispatch({ type: 'previewFailed' })}
                />
              )}
              {preview.status !== 'loaded' && (
                <View style={styles.previewMessage}>
                  {preview.status === 'failed' && (
                    <Image
                      source="sf:exclamationmark.triangle"
                      style={styles.failureIcon}
                      contentFit="contain"
                    />
                  )}
                  <Text allowFontScaling={false} style={styles.message}>
                    {preview.status === 'failed'
                      ? '이미지를 불러오지 못했습니다'
                      : '이미지를 불러오는 중입니다'}
                  </Text>
                </View>
              )}
            </View>
          </View>
          <Pressable
            disabled={photoDisabled}
            onPress={saveToPhotos}
            style={({ pressed }) => [
              styles.photoButton,
              { opacity: photoDisabled || pressed ? 0.5 : 1 },
            ]}
          >
            <View pointerEvents="none" style={styles.photoBackground} />
            {state.isSavingToPhotos ? (
              <ActivityIndicator color={colors.PrimaryText} />
            ) : (
              <Image
                source="sf:square.and.arrow.down"
                style={styles.photoIcon}
                contentFit="contain"
              />
            )}
            <Text allowFontScaling={false} style={styles.photoLabel}>
              사진 앱에 저장
            </Text>
          </Pressable>
          <View style={styles.fields}>
            <View ref={nameRef} style={[styles.field, styles.nameField]}>
              <Text allowFontScaling={false} style={styles.caption}>
                이름
              </Text>
              <TextInput
                allowFontScaling={false}
                style={styles.name}
                {...nameInputProps}
                value={draft.name}
                placeholder="이름 없음"
                placeholderTextColor={colors.Placeholder}
                returnKeyType="done"
                onChangeText={(name) => dispatch({ type: 'nameChanged', name })}
              />
            </View>
            <View style={styles.divider} />
            <View style={styles.pin}>
              <Text allowFontScaling={false} style={styles.pinLabel}>
                고정
              </Text>
              <Switch
                value={draft.isPinned}
                onValueChange={(isPinned) => {
                  dispatch({ type: 'pinnedChanged', isPinned });
                }}
                trackColor={{ true: colors.SwitchOn }}
              />
            </View>
            <View style={styles.divider} />
          </View>
          <ClipDetailDates
            savedValue={formatClipDate(clip.createdAt)}
            lastUsedValue={formatClipDate(clip.lastUsedAt)}
          />
        </View>
      </ScrollView>
      <View style={{ paddingBottom: insets.bottom }}>
        <ClipDetailActionBar
          isBusy={state.isDeleting}
          onDeleteButtonPress={showDeleteSheet}
          onCopyButtonPress={copy}
        />
      </View>
      <ActionSheet
        isVisible={state.isDeleteSheetOpen}
        title="이 이미지를 삭제할까요?"
        message="삭제하면 되돌릴 수 없습니다."
        items={[
          { title: '삭제', role: 'destructive', handler: startDelete },
          { title: '취소', role: 'cancel' },
        ]}
        onClose={() => dispatch({ type: 'deleteSheetClosed' })}
      />
    </View>
  );
}

const styles = StyleSheet.create({
  canvas: { flex: 1, backgroundColor: colors.Canvas },
  scroll: { flex: 1 },
  content: {
    paddingTop: 8,
    paddingBottom: 28,
    paddingHorizontal: spacing.detail,
  },
  card: {
    backgroundColor: colors.Card,
    borderRadius: radius.field,
    borderWidth: 1,
    borderColor: colors.Outline,
    padding: spacing.detail,
    gap: spacing.card,
    overflow: 'hidden',
  },
  meta: {
    fontFamily: 'ui-monospace',
    fontSize: 12,
    fontWeight: '500',
    color: colors.SecondaryText,
  },
  preview: { width: '100%', justifyContent: 'center' },
  previewMessage: { alignItems: 'center' },
  failureIcon: {
    color: colors.SecondaryText,
    width: 32,
    height: 32,
    position: 'absolute',
    bottom: '100%',
    marginBottom: 6,
  },
  message: { fontSize: 14, color: colors.SecondaryText, textAlign: 'center' },
  photoButton: {
    marginTop: spacing.card,
    // 아이콘 영역이 실제 기호보다 높아 세로 여백을 줄여 원본 높이 49pt를 유지한다.
    paddingVertical: 10.5,
    paddingHorizontal: spacing.card,
    borderRadius: radius.button,
    flexDirection: 'row',
    justifyContent: 'center',
    alignItems: 'center',
    gap: 8,
  },
  photoBackground: {
    ...StyleSheet.absoluteFill,
    backgroundColor: colors.Card,
    opacity: 0.2,
    borderRadius: radius.button,
  },
  photoIcon: { width: 24, height: 28, color: colors.PrimaryText },
  photoLabel: { fontSize: 17, color: colors.PrimaryText, flexShrink: 1 },
  fields: { marginTop: spacing.card, marginBottom: 18 },
  field: { paddingVertical: 12, paddingHorizontal: 4, gap: 4 },
  nameField: { gap: 6.5 },
  caption: { ...typography.sectionLabel, color: colors.SecondaryText },
  name: {
    fontSize: 17,
    fontWeight: '500',
    color: colors.PrimaryText,
    flexShrink: 1,
    padding: 0,
  },
  divider: { height: 1, backgroundColor: colors.Outline },
  pin: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingVertical: 12,
    paddingHorizontal: 4,
  },
  pinLabel: {
    flex: 1,
    fontSize: 16,
    fontWeight: '500',
    color: colors.PrimaryText,
  },
});
