import { memo, useCallback, useLayoutEffect, useMemo, useState } from 'react';
import { StyleSheet, View } from 'react-native';
import type { ClipKind } from '../Model/clipRecord';
import {
  ScreenProvider,
  useScreenDispatch,
  useScreenState,
} from '../Shared/State/screenStore';
import { HomeView } from '../Feature/Home/View';
import { SearchView } from '../Feature/Search/View';
import { ImageDetailView } from '../Feature/ImageDetail/View';
import { TextDetailView } from '../Feature/TextDetail/View';
import type { AppNavigation } from './navigation';
import { createAppStore } from './store';

const Home = memo(HomeView);
const Search = memo(SearchView);

export function AppRoot() {
  const [screen] = useState(createAppStore);
  useLayoutEffect(() => {
    screen.start();
    return () => screen.dispose();
  }, [screen]);
  return (
    <ScreenProvider store={screen.store}>
      <AppContent />
    </ScreenProvider>
  );
}

function AppContent() {
  const { isSearchVisible, detail } = useScreenState<AppNavigation>();
  const dispatch = useScreenDispatch();
  const openClip = useCallback(
    (clipID: string, kind: ClipKind) =>
      dispatch({ type: 'clipOpened', detail: { clipID, kind } }),
    [dispatch],
  );
  const closeClip = useCallback(
    () => dispatch({ type: 'clipClosed' }),
    [dispatch],
  );
  const openSearch = useCallback(
    () => dispatch({ type: 'searchOpened' }),
    [dispatch],
  );
  const closeSearch = useCallback(
    () => dispatch({ type: 'searchClosed' }),
    [dispatch],
  );
  // 화면마다 필요한 동작만 타입으로 받으므로 모든 동작을 담은 객체를 한 번만 만들어 넘깁니다.
  const navigation = useMemo(
    () => ({ openClip, openSearch, closeSearch, closeClip }),
    [openClip, openSearch, closeSearch, closeClip],
  );
  return (
    <View style={styles.root}>
      <Home isSearchVisible={isSearchVisible} navigation={navigation} />
      {isSearchVisible && (
        <View style={StyleSheet.absoluteFill}>
          <Search navigation={navigation} />
        </View>
      )}
      {detail?.kind === 'text' && (
        <TextDetailView clipID={detail.clipID} navigation={navigation} />
      )}
      {detail?.kind === 'image' && (
        <ImageDetailView clipID={detail.clipID} navigation={navigation} />
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  root: { flex: 1 },
});
