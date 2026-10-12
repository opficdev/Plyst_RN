import { AppRegistry } from 'react-native';

import App from './App';
import { SearchView } from './src/Feature/Search/SearchView';
import { HomeView } from './src/Feature/Home/View';
import { ToastHost } from './src/Shared/UI';
import { ImageDetailView } from './src/Feature/ImageDetail/ImageDetailView';
import { TextDetailView } from './src/Feature/TextDetail/View';

// PlystRN 이름은 Swift의 ReactNativeViewController moduleName과 공유하는 계약
AppRegistry.registerComponent('PlystRN', () => App);

AppRegistry.registerComponent('TextDetailView', () => TextDetailView);

AppRegistry.registerComponent('ToastHost', () => ToastHost);

AppRegistry.registerComponent('ImageDetailView', () => ImageDetailView);

AppRegistry.registerComponent('HomeView', () => HomeView);

AppRegistry.registerComponent('SearchView', () => SearchView);
