import { useEffect, useState } from 'react';
import { ScrollView, StyleSheet, Switch, Text, View } from 'react-native';
import {
  SafeAreaProvider,
  useSafeAreaInsets,
} from 'react-native-safe-area-context';
import { closeScreen } from 'plyst-bridge';
import { ClipDetailActionBar } from '../components/ClipDetail/ActionBar';
import { ClipDetailDates } from '../components/ClipDetail/Dates';
import { colors, radius, spacing, typography } from '../theme';
import { formatClipDate } from './formatClipDate';
import { loadTextDetail } from './loadTextDetail';
import type { TextDetailResult } from './loadTextDetail';

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
  const insets = useSafeAreaInsets();

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

  const { clip } = state;
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
          <View style={styles.field}>
            <Text allowFontScaling={false} style={styles.caption}>
              이름
            </Text>
            <Text
              allowFontScaling={false}
              style={[styles.name, !clip.name && styles.placeholder]}
            >
              {clip.name || '이름 없음'}
            </Text>
          </View>
          <View style={styles.divider} />
          <View style={styles.pin}>
            <Text allowFontScaling={false} style={styles.pinLabel}>
              고정
            </Text>
            <View pointerEvents="none">
              <Switch
                value={clip.isPinned}
                trackColor={{ true: colors.SwitchOn }}
              />
            </View>
          </View>
          <View style={styles.divider} />
          <View style={styles.field}>
            <Text allowFontScaling={false} style={styles.caption}>
              메모
            </Text>
            <Text
              allowFontScaling={false}
              style={[styles.memo, !clip.memo && styles.placeholder]}
            >
              {clip.memo || '이 내용을 언제 쓰는지 적어 두세요'}
            </Text>
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
    paddingBottom: 21,
    gap: 12,
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
  fields: { marginTop: 10, marginBottom: 18 },
  field: { paddingVertical: 12, paddingHorizontal: 4, gap: 4 },
  caption: { ...typography.sectionLabel, color: colors.SecondaryText },
  name: {
    fontSize: 17,
    fontWeight: '500',
    color: colors.PrimaryText,
    flexShrink: 1,
  },
  placeholder: { color: colors.Placeholder },
  divider: { height: 1, backgroundColor: colors.Outline },
  pin: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingVertical: 14,
    paddingHorizontal: 4,
  },
  pinLabel: {
    flex: 1,
    fontSize: 16,
    fontWeight: '500',
    color: colors.PrimaryText,
  },
  memo: { minHeight: 64, fontSize: 16, color: colors.PrimaryText },
});
