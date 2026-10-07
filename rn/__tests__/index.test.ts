import { AppRegistry } from 'react-native';

import '../index';

test('PlystRN 모듈을 등록한다', () => {
  expect(AppRegistry.getAppKeys()).toContain('PlystRN');
});
