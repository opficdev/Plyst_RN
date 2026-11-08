import { Platform, type TextStyle } from 'react-native';

// Android에는 iOS의 ui-monospace와 Georgia가 없어 같은 성격의 Android 시스템 글꼴로 대체
const monospace: TextStyle = {
  fontFamily: Platform.OS === 'android' ? 'monospace' : 'ui-monospace',
};
const quoteMark: TextStyle = Platform.OS === 'android' ? { fontFamily: 'serif', fontWeight: '700' } : { fontFamily: 'Georgia-Bold' };

export const typography = {
  monospace,
  quoteMark,
  title: {
    fontSize: 17,
    fontWeight: '600',
  },
  sectionLabel: {
    ...monospace,
    fontSize: 11,
    fontWeight: '600',
    letterSpacing: 0.88,
  },
  label: {
    fontSize: 13,
    fontWeight: '600',
  },
  cardName: {
    fontSize: 14.5,
    fontWeight: '600',
  },
  cardBody: {
    fontSize: 14.5,
    fontWeight: '400',
  },
} satisfies Record<string, TextStyle>;
