import type { TextStyle } from 'react-native';

export const typography = {
  title: {
    fontSize: 17,
    fontWeight: '600',
  },
  sectionLabel: {
    fontFamily: 'ui-monospace',
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
