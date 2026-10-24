import type { ComponentProps } from 'react';
import { FlatList, Pressable, StyleSheet, Text, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { colors, spacing, typography } from '../../Theme';
import { ClipPinnedCard, clipCardLongPressDelay } from '../ClipCard';

type HomePinnedRowProps = {
  // 원본 configure(clips:)와 HomePinnedRowViewAction.select의 이름을 유지함
  clips: (ComponentProps<typeof ClipPinnedCard> & {
    id: string;
    onSelect: () => void;
    onShowMenu: () => void;
  })[];
  onViewableIdsChange: (ids: string[]) => void;
};

// 원본 visibleClips()처럼 일부만 보이는 카드도 포함함
// FlatList의 노출 판정으로 최초 배치와 가로 스크롤을 처리함
// 요청 취소는 하지 않음
const viewabilityConfig = { viewAreaCoveragePercentThreshold: 0 };

export function HomePinnedRow({
  clips,
  onViewableIdsChange,
}: HomePinnedRowProps) {
  // 오른쪽 safe area가 있으면 목록 틀이 safe area 안으로 16 들어옴
  // 이때는 구분선과 카드가 잘리는 위치를 safe area 경계에 맞춤
  const isRightInset = 0 < useSafeAreaInsets().right;
  return (
    <View style={styles.container}>
      <View style={[styles.header, isRightInset && styles.insetHeader]}>
        <Text allowFontScaling={false} style={styles.title} numberOfLines={1}>
          고정
        </Text>
        <View style={styles.rule} />
      </View>
      <FlatList
        horizontal
        data={clips}
        keyExtractor={(item) => item.id}
        style={[styles.scrollView, isRightInset && styles.insetScrollView]}
        contentContainerStyle={[
          styles.stack,
          isRightInset && styles.insetStack,
        ]}
        showsHorizontalScrollIndicator={false}
        viewabilityConfig={viewabilityConfig}
        onViewableItemsChanged={({ viewableItems }) =>
          onViewableIdsChange(viewableItems.map(({ item }) => item.id))
        }
        renderItem={({ item }) => (
          <Pressable
            onPress={item.onSelect}
            onLongPress={item.onShowMenu}
            delayLongPress={clipCardLongPressDelay}
          >
            <ClipPinnedCard {...item} onCopyButtonLongPress={item.onShowMenu} />
          </Pressable>
        )}
      />
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    paddingTop: spacing.screen,
    paddingBottom: spacing.detail + 0.6667, // 원본의 레이블 높이 올림에 따른 행 높이를 맞춤
  },
  header: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: spacing.screen,
    gap: 10,
    marginBottom: 14,
  },
  title: {
    ...typography.sectionLabel,
    lineHeight: 13.3333, // 원본 UILabel의 높이를 반영함
    color: colors.SecondaryText,
    flexShrink: 1,
  },
  rule: { height: 1, flex: 1, backgroundColor: colors.Outline },
  scrollView: { height: 76, flexGrow: 0 },
  stack: { paddingHorizontal: spacing.screen, gap: 10 },
  insetHeader: { paddingRight: 16 },
  insetScrollView: { marginRight: 16 },
  insetStack: { paddingRight: 0 },
});
