import { AppRegistry } from 'react-native';
import '../index';

jest.mock('plyst-bridge', () => ({
  getClip: jest.fn(),
  getClipImagePreview: jest.fn(),
  saveClipImageToPhotos: jest.fn(),
  copyClip: jest.fn(),
  deleteClip: jest.fn(),
  closeScreen: jest.fn(),
  setSaveEnabled: jest.fn(),
  subscribeSave: jest.fn(() => ({ remove: jest.fn() })),
  subscribeClipChanges: jest.fn(() => ({ remove: jest.fn() })),
  updateClip: jest.fn(),
  subscribeToastRequests: jest.fn(),
}));

jest.mock('@shopify/flash-list', () => ({ FlashList: () => null }));

test('PlystRN 모듈을 등록한다', () => {
  expect(AppRegistry.getAppKeys()).toContain('PlystRN');
});

test('TextDetailView 모듈을 등록한다', () => {
  expect(AppRegistry.getAppKeys()).toContain('TextDetailView');
});

test('ImageDetailView 모듈을 등록한다', () => {
  expect(AppRegistry.getAppKeys()).toContain('ImageDetailView');
});

test('HomeView 모듈을 등록한다', () => {
  expect(AppRegistry.getAppKeys()).toContain('HomeView');
});
