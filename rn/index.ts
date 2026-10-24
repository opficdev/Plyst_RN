import { AppRegistry } from 'react-native';

import App from './App';
import { AppRoot } from './src/App/Root';
import { ToastHost } from './src/Shared/UI';

// PlystRN 이름은 Swift의 ReactNativeViewController moduleName과 공유하는 이름
AppRegistry.registerComponent('PlystRN', () => App);

AppRegistry.registerComponent('ToastHost', () => ToastHost);

// AppRoot 이름은 SceneComposition이 ReactNativeBrownfield.shared.view에 넘기는 moduleName과 같음
AppRegistry.registerComponent('AppRoot', () => AppRoot);
