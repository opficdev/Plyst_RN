import { memo, useCallback, useLayoutEffect, useMemo, useState } from 'react';
import { StyleSheet, View } from 'react-native';
import {
  SafeAreaProvider,
  initialWindowMetrics,
} from 'react-native-safe-area-context';
import { ScreenStack, ScreenStackItem } from 'react-native-screens';
import type { ScreenStackHeaderConfigProps } from 'react-native-screens';
import { isDuoDevice } from 'plyst-bridge';
import type { ClipKind } from '../Model/clipRecord';
import {
  ScreenProvider,
  useScreenDispatch,
  useScreenState,
} from '../Shared/State/screenStore';
import { HomeView } from '../Feature/Home/View';
import { NavigationBarTitle } from '../Feature/Home/NavigationBarTitle';
import { SearchView } from '../Feature/Search/View';
import { ImageDetailView } from '../Feature/ImageDetail/View';
import { TextDetailView } from '../Feature/TextDetail/View';
import { navigationActions as actions } from './navigation';
import type { AppNavigation } from './navigation';
import { createAppStore } from './store';

const Home = memo(HomeView);
const Search = memo(SearchView);

// iPhone Duo는 오른쪽 위 카메라를 피해 시스템이 내비게이션 바 항목을 놓도록 헤더를 보이고 RN 버튼은 그리지 않음
// 다른 기기는 헤더를 숨기고 지금처럼 RN 버튼을 그림
// 값은 프로세스가 끝날 때까지 바뀌지 않음
const usesSystemBar = isDuoDevice();

// 항목은 각 화면이 PlystNavigationBarButton으로 넣으므로 헤더 설정에는 항목을 두지 않음
// iPhone Duo는 로고와 제목도 시스템이 검색 항목과 같은 바 줄에 놓도록 왼쪽 항목으로 넣음
// 검색 화면은 자기 스택 항목에 항목을 두므로 홈 항목은 검색이 열려도 빼지 않음
const homeHeader: ScreenStackHeaderConfigProps = {
  hidden: !usesSystemBar,
  translucent: true,
  hideShadow: true,
  backgroundColor: 'transparent',
  children: usesSystemBar ? <NavigationBarTitle /> : undefined,
};

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
      dispatch(actions.clipOpened({ clipID, kind })),
    [dispatch],
  );
  const closeClip = useCallback(
    () => dispatch(actions.clipClosed()),
    [dispatch],
  );
  const openSearch = useCallback(
    () => dispatch(actions.searchOpened()),
    [dispatch],
  );
  const closeSearch = useCallback(
    () => dispatch(actions.searchClosed()),
    [dispatch],
  );
  // 화면마다 필요한 동작만 타입으로 받으므로 모든 동작을 담은 객체를 한 번만 만들어 넘김
  const navigation = useMemo(
    () => ({ openClip, openSearch, closeSearch, closeClip }),
    [openClip, openSearch, closeSearch, closeClip],
  );
  const stack = (
    <ScreenStack style={styles.root}>
      <ScreenStackItem
        screenId="home"
        headerConfig={homeHeader}
        style={StyleSheet.absoluteFill}
      >
        <Home
          isSearchVisible={isSearchVisible}
          usesSystemBar={usesSystemBar}
          navigation={navigation}
        />
        {!usesSystemBar && isSearchVisible && (
          <View style={StyleSheet.absoluteFill}>
            <Search usesSystemBar={usesSystemBar} navigation={navigation} />
          </View>
        )}
      </ScreenStackItem>
      {/* iPhone Duo는 검색 화면이 자기 ScreenStackItem을 그리므로 ScreenStack의 직접 자식으로 붙임 */}
      {usesSystemBar && isSearchVisible && (
        <Search usesSystemBar={usesSystemBar} navigation={navigation} />
      )}
      {detail?.kind === 'text' && (
        <TextDetailView
          clipID={detail.clipID}
          usesSystemBar={usesSystemBar}
          navigation={navigation}
        />
      )}
      {detail?.kind === 'image' && (
        <ImageDetailView
          clipID={detail.clipID}
          usesSystemBar={usesSystemBar}
          navigation={navigation}
        />
      )}
    </ScreenStack>
  );
  // iPhone Duo는 검색 화면 헤더가 항목 안쪽 provider 바깥이라 앱 전체의 오른쪽 안전 영역을 여기서 제공함
  if (!usesSystemBar) return stack;
  return (
    <SafeAreaProvider style={styles.root} initialMetrics={initialWindowMetrics}>
      {stack}
    </SafeAreaProvider>
  );
}

const styles = StyleSheet.create({
  root: { flex: 1 },
});
