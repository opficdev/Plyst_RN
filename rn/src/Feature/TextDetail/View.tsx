import { useEffect, useLayoutEffect, useRef, useState } from 'react';
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
import { closeScreen, setSaveEnabled } from 'plyst-bridge';
import { ActionSheet } from '../../Shared/UI';
import {
  ClipDetailActionBar,
  ClipDetailDates,
} from '../../Shared/UI/ClipDetail';
import { colors, radius, spacing, typography } from '../../Shared/Theme';
import { formatClipDate } from '../ClipDetail/formatDate';
import { canSave } from './draft';
import type { TextDetailState } from './draft';
import { useScrollFieldIntoView } from '../ClipDetail/useScrollFieldIntoView';

import {
  ScreenProvider,
  useScreenState,
  useScreenDispatch,
} from '../../Shared/State/screenStore';
import { createTextDetailStore } from './store';
import type { TextDetailStoreState } from './store';
import { textDetailActions as actions } from './actions';

type TextDetailViewProps = { clipID: string };

export function TextDetailView({ clipID }: TextDetailViewProps) {
  return (
    <SafeAreaProvider style={styles.canvas}>
      <TextDetailRoot key={clipID} clipID={clipID} />
    </SafeAreaProvider>
  );
}

function TextDetailRoot({ clipID }: TextDetailViewProps) {
  const [screen] = useState(() => createTextDetailStore(clipID));
  useLayoutEffect(() => {
    screen.start();
    return () => screen.dispose();
  }, [screen]);
  useEffect(() => {
    screen.store.dispatch(actions.viewDidLoad());
  }, [screen]);
  return (
    <ScreenProvider store={screen.store}>
      <TextDetailContent />
    </ScreenProvider>
  );
}

function TextDetailContent() {
  const state = useScreenState<TextDetailStoreState>();
  const didClose = useRef(false);
  const isClosed = state === 'closed' || !!(state?.isRemoved || state?.isSaved);
  useEffect(() => {
    if (didClose.current || !isClosed) return;
    didClose.current = true;
    closeScreen();
  }, [isClosed]);
  if (state === 'closed') return null;
  if (state === null) return <View style={styles.canvas} />;
  return <TextDetailEditor state={state} />;
}

function TextDetailEditor({ state }: { state: TextDetailState }) {
  const dispatch = useScreenDispatch();
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

  useEffect(() => {
    setSaveEnabled(isSaveEnabled);
  }, [isSaveEnabled]);

  function showDeleteSheet() {
    if (state.isDeleting || state.isRemoved || state.isDeleteSheetOpen) return;
    dispatch({ type: 'deleteSheetShown' });
  }
  const copy = () => dispatch(actions.copy());
  const startDelete = () => dispatch(actions.delete());

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
                onValueChange={(isPinned) => {
                  dispatch({ type: 'pinnedChanged', isPinned });
                }}
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
