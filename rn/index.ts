import { AppRegistry } from 'react-native';

import App from './App';
import { SearchView } from './src/screens/SearchView';
import { HomeView } from './src/screens/HomeView';
import { ToastHost } from './src/components';
import { ImageDetailView } from './src/screens/ImageDetailView';
import { TextDetailView } from './src/screens/TextDetailView';

// PlystRN 이름은 Swift의 ReactNativeViewController moduleName과 공유하는 계약
AppRegistry.registerComponent('PlystRN', () => App);

AppRegistry.registerComponent('TextDetailView', () => TextDetailView);

AppRegistry.registerComponent('ToastHost', () => ToastHost);

AppRegistry.registerComponent('ImageDetailView', () => ImageDetailView);

AppRegistry.registerComponent('HomeView', () => HomeView);

AppRegistry.registerComponent('SearchView', () => SearchView);
