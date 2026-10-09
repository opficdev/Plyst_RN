import { AppRegistry } from 'react-native';

jest.mock('plyst-bridge', () => ({
  getClip: jest.fn(),
  copyClip: jest.fn(),
  deleteClip: jest.fn(),
  closeScreen: jest.fn(),
  setSaveEnabled: jest.fn(),
  subscribeSave: jest.fn(() => ({ remove: jest.fn() })),
  subscribeClipChanges: jest.fn(() => ({ remove: jest.fn() })),
  updateClip: jest.fn(),
  subscribeToastRequests: jest.fn(),
}));

import '../index';

test('PlystRN 모듈을 등록한다', () => {
  expect(AppRegistry.getAppKeys()).toContain('PlystRN');
});

test('TextDetailView 모듈을 등록한다', () => {
  expect(AppRegistry.getAppKeys()).toContain('TextDetailView');
});
