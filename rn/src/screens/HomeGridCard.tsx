import { createContext, useContext } from 'react';
import type { Ref } from 'react';
import { Pressable, StyleSheet, View } from 'react-native';
import type { ViewProps } from 'react-native';

import { clipCardLongPressDelay } from '../components/ClipCard';

const leftColumn = createContext(true);

// 항목 순번 대신 실제 열 위치를 사용합니다. 전체 너비 항목에는 여백을 적용하지 않습니다.
export function HomeListCell({
  children,
  style,
  index: _index,
  ...props
}: ViewProps & { index: number; ref?: Ref<View> }) {
  return (
    <View {...props} style={style}>
      <leftColumn.Provider value={StyleSheet.flatten(style)?.left === 0}>
        {children}
      </leftColumn.Provider>
    </View>
  );
}

export function HomeGridCard({
  children,
  onPress,
  onShowMenu,
}: {
  children: React.ReactNode;
  onPress: () => void;
  onShowMenu: () => void;
}) {
  const isLeft = useContext(leftColumn);
  return (
    <View style={[styles.card, isLeft ? styles.leftCard : styles.rightCard]}>
      <Pressable
        onPress={onPress}
        onLongPress={onShowMenu}
        delayLongPress={clipCardLongPressDelay}
      >
        {children}
      </Pressable>
    </View>
  );
}

const styles = StyleSheet.create({
  card: { paddingBottom: 10 },
  leftCard: { marginLeft: 16, marginRight: 5 },
  rightCard: { marginLeft: 5, marginRight: 16 },
});
