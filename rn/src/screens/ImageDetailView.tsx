import {
  useEffect,
  useLayoutEffect,
  useReducer,
  useRef,
  useState,
} from 'react';
import type { Dispatch, RefObject } from 'react';
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
import {
  closeScreen,
  setSaveEnabled,
  subscribeClipChanges,
  subscribeSave,
} from 'plyst-bridge';
import { ActionSheet, showToast } from '../components';
import { ClipDetailActionBar, ClipDetailDates } from '../components/ClipDetail';
import { colors, radius, spacing, typography } from '../theme';
import { copyClipDetail } from './copyClipDetail';
import { deleteClipDetail } from './deleteClipDetail';
import { formatClipDate } from './formatClipDate';
import { loadImageDetail } from './loadImageDetail';
import { saveImageDetail } from './saveImageDetail';
import { loadImageDetailPreview } from './loadImageDetailPreview';
import { saveImageDetailToPhotos } from './saveImageDetailToPhotos';
import { canSave, initialState, reduce } from './imageDetailDraft';
import type { ImageDetailAction, ImageDetailState } from './imageDetailDraft';
import { createClipDetailRefresher } from './clipDetailRefresher';
import { useScrollFieldIntoView } from './useScrollFieldIntoView';

type ImageDetailViewProps = { clipID: string };
type State = ImageDetailState | null | 'closed';
type Action = ImageDetailAction | { type: 'loadFailed' };

function reduceContent(state: State, action: Action): State {
  if (state === 'closed') return state;
  if (action.type === 'loadFailed') return state ?? 'closed';
  if (state === null) {
    if (action.type === 'clipLoaded') return initialState(action.clip);
    return action.type === 'removed' ? 'closed' : state;
  }
  if (action.type === 'clipLoaded' && (state.isRemoved || state.isSaved)) {
    return state;
  }
  return reduce(state, action);
}

export function ImageDetailView({ clipID }: ImageDetailViewProps) {
  return (
    <SafeAreaProvider style={styles.canvas}>
      <ImageDetailContent key={clipID} clipID={clipID} />
    </SafeAreaProvider>
  );
}

function ImageDetailContent({ clipID }: ImageDetailViewProps) {
  const [state, dispatch] = useReducer(reduceContent, null);
  const didClose = useRef(false);
  const isClosed = state === 'closed' || !!(state?.isRemoved || state?.isSaved);
  const closedRef = useRef(isClosed);

  useLayoutEffect(() => {
    closedRef.current = isClosed;
  }, [isClosed]);

  useEffect(() => {
    if (didClose.current || !isClosed) return;
    didClose.current = true;
    closeScreen();
  }, [isClosed]);

  useEffect(() => {
    let removed = false;
    let previewRequested = false;
    const isStopped = () => removed || closedRef.current || didClose.current;
    const refresher = createClipDetailRefresher({
      load: () => loadImageDetail(clipID),
      onResult: (result) => {
        if (isStopped()) return;
        if (result.status === 'loaded') {
          dispatch({ type: 'clipLoaded', clip: result.clip });
          if (!previewRequested) {
            previewRequested = true;
            void loadImageDetailPreview(clipID).then((preview) => {
              if (isStopped()) return;
              dispatch(
                preview.status === 'loaded'
                  ? { type: 'previewReady', uri: preview.uri }
                  : { type: 'previewFailed' },
              );
            });
          }
        } else if (result.status === 'missing') {
          removed = true;
          dispatch({ type: 'removed' });
        } else {
          dispatch({ type: 'loadFailed' });
        }
      },
    });
    const subscription = subscribeClipChanges((change) => {
      if (change.id !== clipID || isStopped()) return;
      if (change.kind === 'updated') void refresher.refresh();
      else {
        removed = true;
        refresher.invalidate();
        dispatch({ type: 'removed' });
      }
    });
    if (!isStopped()) void refresher.refresh();
    return () => {
      removed = true;
      refresher.dispose();
      subscription.remove();
    };
  }, [clipID]);

  if (state === 'closed') return null;
  if (state === null) return <View style={styles.canvas} />;

  return (
    <ImageDetailEditor
      clipID={clipID}
      state={state}
      dispatch={dispatch}
      didClose={didClose}
    />
  );
}

function ImageDetailEditor({
  clipID,
  state,
  dispatch,
  didClose,
}: ImageDetailViewProps & {
  state: ImageDetailState;
  dispatch: Dispatch<ImageDetailAction>;
  didClose: RefObject<boolean>;
}) {
  const stateRef = useRef(state);
  const savingRef = useRef(false);
  const deletingRef = useRef(false);
  const photoSavingRef = useRef(false);
  const [previewWidth, setPreviewWidth] = useState(0);
  const window = useWindowDimensions();
  const activeRef = useRef(true);
  const insets = useSafeAreaInsets();
  const { contentRef, nameRef, nameInputProps, scrollProps } =
    useScrollFieldIntoView();
  const isSaveEnabled = canSave(state);

  useLayoutEffect(() => {
    stateRef.current = state;
  }, [state]);

  useEffect(() => {
    activeRef.current = true;
    return () => {
      activeRef.current = false;
    };
  }, []);

  useEffect(() => {
    setSaveEnabled(isSaveEnabled);
  }, [isSaveEnabled]);

  useEffect(() => {
    let active = true;
    const subscription = subscribeSave(() => {
      const current = stateRef.current;
      if (
        !active ||
        didClose.current ||
        savingRef.current ||
        !canSave(current)
      ) {
        return;
      }
      savingRef.current = true;
      dispatch({ type: 'saveStarted' });
      void saveImageDetail(clipID, current.draft, current.clip.memo).then(
        (result) => {
          savingRef.current = false;
          switch (result.status) {
            case 'saved':
              if (active) dispatch({ type: 'saved', clip: result.clip });
              showToast('저장했습니다', true);
              break;
            case 'removed':
              if (active) dispatch({ type: 'removed' });
              break;
            case 'failed':
              if (active) dispatch({ type: 'saveFailed' });
              showToast('저장하지 못했습니다', false);
              break;
          }
        },
      );
    });
    return () => {
      active = false;
      subscription.remove();
    };
  }, [clipID, didClose, dispatch]);

  function copy() {
    const current = stateRef.current;
    if (current.isDeleting || current.isRemoved) return;
    void copyClipDetail(clipID).then((result) => {
      if (result === 'copied') {
        showToast('클립보드에 복사했습니다', true);
      } else {
        showToast('클립보드에 복사하지 못했습니다', false);
      }
    });
  }

  function showDeleteSheet() {
    const current = stateRef.current;
    if (current.isDeleting || current.isRemoved || current.isDeleteSheetOpen) {
      return;
    }
    dispatch({ type: 'deleteSheetShown' });
  }

  function startDelete() {
    const current = stateRef.current;
    if (deletingRef.current || current.isDeleting || current.isRemoved) return;
    deletingRef.current = true;
    dispatch({ type: 'deleteStarted' });
    void deleteClipDetail(clipID).then((result) => {
      deletingRef.current = false;
      if (result === 'deleted') {
        if (activeRef.current) dispatch({ type: 'removed' });
      } else {
        if (activeRef.current) dispatch({ type: 'deleteFailed' });
        showToast('삭제하지 못했습니다', false);
      }
    });
  }

  function saveToPhotos() {
    const current = stateRef.current;
    if (
      photoSavingRef.current ||
      current.isSavingToPhotos ||
      current.isDeleting ||
      current.isRemoved
    ) {
      return;
    }
    photoSavingRef.current = true;
    dispatch({ type: 'photoSaveStarted' });
    void saveImageDetailToPhotos(clipID).then((result) => {
      photoSavingRef.current = false;
      if (result.status === 'removed') {
        if (activeRef.current) dispatch({ type: 'removed' });
      } else {
        if (activeRef.current) dispatch({ type: 'photoSaveFinished' });
        showToast(result.message, result.isSuccess);
      }
    });
  }

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
                onValueChange={(isPinned) =>
                  dispatch({ type: 'pinnedChanged', isPinned })
                }
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
