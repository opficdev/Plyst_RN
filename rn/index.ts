import { AppRegistry } from 'react-native';

import App from './App';
import { TextDetailView } from './src/screens/TextDetailView';

// PlystRN 이름은 Swift의 ReactNativeViewController moduleName과 공유하는 계약
AppRegistry.registerComponent('PlystRN', () => App);

AppRegistry.registerComponent('TextDetailView', () => TextDetailView);
