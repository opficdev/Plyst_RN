import type { ComponentProps } from 'react';
import { FlatList, Pressable, StyleSheet, Text, View } from 'react-native';
import { colors, spacing, typography } from '../../theme';
import { ClipPinnedCard } from '../ClipCard';

type HomePinnedRowProps = {
  // 원본 configure(clips:)와 HomePinnedRowViewAction.select의 이름을 유지한다.
  clips: (ComponentProps<typeof ClipPinnedCard> & {
    id: string;
    onSelect: () => void;
  })[];
  onViewableIdsChange: (ids: string[]) => void;
};

// 원본 visibleClips()처럼 일부만 보이는 카드도 포함한다.
// FlatList의 노출 판정으로 최초 배치와 가로 스크롤을 처리한다. 요청 취소는 하지 않는다.
const viewabilityConfig = { viewAreaCoveragePercentThreshold: 0 };

export function HomePinnedRow({
  clips,
  onViewableIdsChange,
}: HomePinnedRowProps) {
  return (
    <View style={styles.container}>
      <View style={styles.header}>
        <Text style={styles.title} numberOfLines={1}>
          고정
        </Text>
        <View style={styles.rule} />
      </View>
      <FlatList
        horizontal
        data={clips}
        keyExtractor={(item) => item.id}
        style={styles.scrollView}
        contentContainerStyle={styles.stack}
        showsHorizontalScrollIndicator={false}
        viewabilityConfig={viewabilityConfig}
        onViewableItemsChanged={({ viewableItems }) =>
          onViewableIdsChange(viewableItems.map(({ item }) => item.id))
        }
        renderItem={({ item }) => (
          <Pressable onPress={item.onSelect}>
            <ClipPinnedCard {...item} />
          </Pressable>
        )}
      />
    </View>
  );
}

const styles = StyleSheet.create({
  container: { paddingTop: spacing.screen, paddingBottom: spacing.detail },
  header: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: spacing.screen,
    gap: 10,
    marginBottom: 14,
  },
  title: {
    ...typography.sectionLabel,
    color: colors.SecondaryText,
    flexShrink: 1,
  },
  rule: { height: 1, flex: 1, backgroundColor: colors.Outline },
  scrollView: { height: 76, flexGrow: 0 },
  stack: { paddingHorizontal: spacing.screen, gap: 10 },
});
