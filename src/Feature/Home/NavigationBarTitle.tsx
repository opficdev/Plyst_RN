import { StyleSheet } from 'react-native';
import { ScreenStackHeaderLeftView } from 'react-native-screens';
import { HomeTitle } from '../../Shared/UI';

// 시스템이 검색 항목과 같은 바 줄에 놓도록 헤더 왼쪽 항목으로 로고와 제목을 그림
export function NavigationBarTitle() {
  return (
    <ScreenStackHeaderLeftView hidesSharedBackground style={styles.container}>
      <HomeTitle />
    </ScreenStackHeaderLeftView>
  );
}

const styles = StyleSheet.create({
  container: { flexDirection: 'row', alignItems: 'center', gap: 10 },
});
