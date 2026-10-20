import { AppRegistry } from 'react-native';
import '../index';

jest.mock('plyst-bridge', () => ({
  getClip: jest.fn(),
  getClipImagePreview: jest.fn(),
  saveClipImageToPhotos: jest.fn(),
  copyClip: jest.fn(),
  deleteClip: jest.fn(),
  isDuoDevice: jest.fn(() => false),
  subscribeClipboardSaveRequests: jest.fn(() => ({ remove: jest.fn() })),
  subscribeClipChanges: jest.fn(() => ({ remove: jest.fn() })),
  updateClip: jest.fn(),
}));

jest.mock('@shopify/flash-list', () => ({ FlashList: () => null }));

test('PlystRN 모듈을 등록한다', () => {
  expect(AppRegistry.getAppKeys()).toContain('PlystRN');
});

test('ToastHost 모듈을 등록한다', () => {
  expect(AppRegistry.getAppKeys()).toContain('ToastHost');
});

test('AppRoot 모듈 하나가 화면 루트를 대신한다', () => {
  expect(AppRegistry.getAppKeys()).toContain('AppRoot');
  for (const name of [
    'HomeView',
    'SearchView',
    'TextDetailView',
    'ImageDetailView',
  ]) {
    expect(AppRegistry.getAppKeys()).not.toContain(name);
  }
});
