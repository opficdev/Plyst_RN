import { StyleSheet, View } from 'react-native';
import { colors } from './src/Shared/Theme';

export default function App() {
  return <View style={styles.container} />;
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: colors.Canvas,
  },
});
