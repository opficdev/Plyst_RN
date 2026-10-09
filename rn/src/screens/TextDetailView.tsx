import { useEffect, useLayoutEffect, useReducer, useRef } from 'react';
import type { Dispatch, RefObject } from 'react';
import {
  ScrollView,
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
import { loadTextDetail } from './loadTextDetail';
import { saveTextDetail } from './saveTextDetail';
import { canSave, initialState, reduce } from './textDetailDraft';
import type { TextDetailAction, TextDetailState } from './textDetailDraft';
import { createClipDetailRefresher } from './clipDetailRefresher';
import { useScrollFieldIntoView } from './useScrollFieldIntoView';

type TextDetailViewProps = { clipID: string };
type State = TextDetailState | null | 'closed';
type Action = TextDetailAction | { type: 'loadFailed' };

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

export function TextDetailView({ clipID }: TextDetailViewProps) {
  return (
    <SafeAreaProvider style={styles.canvas}>
      <TextDetailContent key={clipID} clipID={clipID} />
    </SafeAreaProvider>
  );
}

function TextDetailContent({ clipID }: TextDetailViewProps) {
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
    const isStopped = () => removed || closedRef.current || didClose.current;
    const refresher = createClipDetailRefresher({
      load: () => loadTextDetail(clipID),
      onResult: (result) => {
        if (isStopped()) return;
        if (result.status === 'loaded') {
          dispatch({ type: 'clipLoaded', clip: result.clip });
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
    <TextDetailEditor
      clipID={clipID}
      state={state}
      dispatch={dispatch}
      didClose={didClose}
    />
  );
}

function TextDetailEditor({
  clipID,
  state,
  dispatch,
  didClose,
}: TextDetailViewProps & {
  state: TextDetailState;
  dispatch: Dispatch<TextDetailAction>;
  didClose: RefObject<boolean>;
}) {
  const stateRef = useRef(state);
  const savingRef = useRef(false);
  const deletingRef = useRef(false);
  const activeRef = useRef(true);
  const insets = useSafeAreaInsets();
  const {
    contentRef,
    nameRef,
    memoRef,
    nameInputProps,
    memoInputProps,
    revealMemo,
    scrollProps,
  } = useScrollFieldIntoView();
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
      void saveTextDetail(clipID, current.draft).then((result) => {
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
      });
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

  const { clip, draft } = state;
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
              {`${clip.isPinned ? '고정됨 · ' : ''}${clip.characterCount}자`}
            </Text>
            <Text allowFontScaling={false} style={styles.body}>
              {clip.text}
            </Text>
          </View>
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
            <View ref={memoRef} style={[styles.field, styles.memoField]}>
              <Text allowFontScaling={false} style={styles.caption}>
                메모
              </Text>
              <TextInput
                allowFontScaling={false}
                style={styles.memo}
                {...memoInputProps}
                value={draft.memo}
                placeholder="이 내용을 언제 쓰는지 적어 두세요"
                placeholderTextColor={colors.Placeholder}
                multiline
                scrollEnabled={false}
                onChangeText={(memo) => {
                  dispatch({ type: 'memoChanged', memo });
                  revealMemo();
                }}
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
        title="이 텍스트를 삭제할까요?"
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
    borderRadius: radius.card,
    borderWidth: 1,
    borderColor: colors.Outline,
    paddingTop: 17,
    paddingHorizontal: 19,
    paddingBottom: 16,
    gap: 17,
  },
  meta: {
    fontFamily: 'ui-monospace',
    fontSize: 11.5,
    fontWeight: '500',
    color: colors.SecondaryText,
  },
  body: {
    fontSize: 22,
    fontWeight: '500',
    lineHeight: 35,
    color: colors.PrimaryText,
  },
  fields: { marginTop: 11, marginBottom: 18 },
  field: { paddingVertical: 12, paddingHorizontal: 4, gap: 4 },
  nameField: { paddingTop: 11.67, paddingBottom: 12.33, gap: 6.93 },
  memoField: { paddingTop: 12.67, paddingBottom: 11.67, gap: 5.9 },
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
    paddingVertical: 14,
    paddingLeft: 4,
    paddingRight: 1.8,
  },
  pinLabel: {
    flex: 1,
    fontSize: 16,
    fontWeight: '500',
    color: colors.PrimaryText,
  },
  memo: {
    minHeight: 64,
    fontSize: 16,
    color: colors.PrimaryText,
    textAlignVertical: 'top',
    padding: 0,
  },
});
