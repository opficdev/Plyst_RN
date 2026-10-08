import { AppRegistry } from 'react-native';
import { subscribeToastRequests } from 'plyst-bridge';

import App from './App';
import { showToast, ToastHost } from './src/components';
import { TextDetailView } from './src/screens/TextDetailView';

subscribeToastRequests(({ message, isSuccess }) =>
  showToast(message, isSuccess),
);

// PlystRN 이름은 Swift의 ReactNativeViewController moduleName과 공유하는 계약
AppRegistry.registerComponent('PlystRN', () => App);

AppRegistry.registerComponent('TextDetailView', () => TextDetailView);

AppRegistry.registerComponent('ToastHost', () => ToastHost);
