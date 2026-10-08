import {
  useEffect,
  useLayoutEffect,
  useReducer,
  useRef,
  useState,
} from 'react';
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
import { closeScreen, setSaveEnabled, subscribeSave } from 'plyst-bridge';
import type { ClipRecord } from 'plyst-bridge';
import { showToast } from '../components';
import { ClipDetailActionBar, ClipDetailDates } from '../components/ClipDetail';
import { colors, radius, spacing, typography } from '../theme';
import { formatClipDate } from './formatClipDate';
import { loadTextDetail } from './loadTextDetail';
import type { TextDetailResult } from './loadTextDetail';
import { saveTextDetail } from './saveTextDetail';
import { canSave, initialState, reduce } from './textDetailDraft';

type TextDetailViewProps = { clipID: string };
type State = { status: 'loading' } | TextDetailResult;
const ignorePress = () => {};

export function TextDetailView({ clipID }: TextDetailViewProps) {
  return (
    <SafeAreaProvider style={styles.canvas}>
      <TextDetailContent key={clipID} clipID={clipID} />
    </SafeAreaProvider>
  );
}

function TextDetailContent({ clipID }: TextDetailViewProps) {
  const [state, setState] = useState<State>({ status: 'loading' });

  useEffect(() => {
    let active = true;
    void loadTextDetail(clipID).then((result) => {
      if (!active) return;
      setState(result);
      if (result.status !== 'loaded') closeScreen();
    });
    return () => {
      active = false;
    };
  }, [clipID]);

  if (state.status === 'missing' || state.status === 'failed') return null;
  if (state.status === 'loading') return <View style={styles.canvas} />;

  return <TextDetailEditor clipID={clipID} clip={state.clip} />;
}

function TextDetailEditor({
  clipID,
  clip: initialClip,
}: TextDetailViewProps & { clip: ClipRecord }) {
  const [state, dispatch] = useReducer(reduce, initialClip, initialState);
  const stateRef = useRef(state);
  const savingRef = useRef(false);
  const didClose = useRef(false);
  const insets = useSafeAreaInsets();
  const isSaveEnabled = canSave(state);

  useLayoutEffect(() => {
    stateRef.current = state;
  }, [state]);

  useEffect(() => {
    setSaveEnabled(isSaveEnabled);
  }, [isSaveEnabled]);

  useEffect(() => {
    if (didClose.current || (!state.isRemoved && !state.isSaved)) return;
    didClose.current = true;
    closeScreen();
  }, [state.isRemoved, state.isSaved]);

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
  }, [clipID]);

  const { clip, draft } = state;
  return (
    <View style={styles.canvas}>
      <ScrollView
        style={styles.scroll}
        contentContainerStyle={styles.content}
        contentInsetAdjustmentBehavior="never"
      >
        <View style={styles.card}>
          <Text allowFontScaling={false} style={styles.meta}>
            {`${clip.isPinned ? '고정됨 · ' : ''}${clip.characterCount}자`}
          </Text>
          <Text allowFontScaling={false} style={styles.body}>
            {clip.text}
          </Text>
        </View>
        <View style={styles.fields}>
          <View style={[styles.field, styles.nameField]}>
            <Text allowFontScaling={false} style={styles.caption}>
              이름
            </Text>
            <TextInput
              allowFontScaling={false}
              style={styles.name}
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
          <View style={[styles.field, styles.memoField]}>
            <Text allowFontScaling={false} style={styles.caption}>
              메모
            </Text>
            <TextInput
              allowFontScaling={false}
              style={styles.memo}
              value={draft.memo}
              placeholder="이 내용을 언제 쓰는지 적어 두세요"
              placeholderTextColor={colors.Placeholder}
              multiline
              scrollEnabled={false}
              onChangeText={(memo) => dispatch({ type: 'memoChanged', memo })}
            />
          </View>
          <View style={styles.divider} />
        </View>
        <ClipDetailDates
          savedValue={formatClipDate(clip.createdAt)}
          lastUsedValue={formatClipDate(clip.lastUsedAt)}
        />
      </ScrollView>
      <View pointerEvents="none" style={{ paddingBottom: insets.bottom }}>
        <ClipDetailActionBar
          onDeleteButtonPress={ignorePress}
          onCopyButtonPress={ignorePress}
        />
      </View>
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
  nameField: { gap: 6.6 },
  memoField: { gap: 4.9 },
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
