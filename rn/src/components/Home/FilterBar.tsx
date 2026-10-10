import { useState } from 'react';
import { Pressable, ScrollView, StyleSheet, Text } from 'react-native';
import { colors, spacing, typography } from '../../theme';

type HomeFilterBarProps<Key extends string> = {
  chips: { key: Key; title: string }[];
  selectedKey: Key;
  // HomeFilterBarViewAction.select의 의미를 유지한다.
  onSelect: (key: Key) => void;
};

export function HomeFilterBar<Key extends string>(
  props: HomeFilterBarProps<Key>,
) {
  return (
    <HomeFilterChips
      key={JSON.stringify(props.chips.map(({ title }) => title))}
      {...props}
    />
  );
}

function HomeFilterChips<Key extends string>({
  chips,
  selectedKey,
  onSelect,
}: HomeFilterBarProps<Key>) {
  const [maxWidth, setMaxWidth] = useState(0);

  return (
    <ScrollView
      horizontal
      style={styles.scrollView}
      contentContainerStyle={styles.stack}
      showsHorizontalScrollIndicator={false}
      alwaysBounceHorizontal
    >
      {chips.map(({ key, title }) => (
        <Pressable
          key={key}
          style={[
            styles.button,
            { minWidth: maxWidth },
            key === selectedKey && styles.selectedButton,
          ]}
          onLayout={({ nativeEvent }) => {
            const { width } = nativeEvent.layout;
            setMaxWidth((current) => Math.max(current, width));
          }}
          onPress={() => onSelect(key)}
        >
          <Text
            style={[styles.title, key === selectedKey && styles.selectedTitle]}
            numberOfLines={1}
          >
            {title}
          </Text>
        </Pressable>
      ))}
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  scrollView: { height: 40, flexGrow: 0, flexShrink: 0 },
  stack: { paddingHorizontal: spacing.screen, gap: 8 },
  button: {
    justifyContent: 'center',
    alignItems: 'center',
    paddingVertical: 8,
    paddingHorizontal: 14 - 1,
    borderRadius: 999,
    backgroundColor: colors.Card,
    borderWidth: 1,
    borderColor: colors.Outline,
  },
  selectedButton: {
    backgroundColor: colors.BottomBar,
    borderColor: colors.BottomBar,
  },
  title: { ...typography.label, color: colors.PrimaryText },
  selectedTitle: { color: colors.BottomText },
});
