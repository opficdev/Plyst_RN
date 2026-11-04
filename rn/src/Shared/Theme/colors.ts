import { Platform, PlatformColor } from 'react-native';

// Android는 prebuild가 에셋 카탈로그에서 만든 같은 이름의 color 리소스를 읽음
function assetColor(name: string) {
  return PlatformColor(Platform.OS === 'android' ? `@color/${name}` : name);
}

export const colors = {
  BottomBar: assetColor('HomeBottomBar'),
  BottomText: assetColor('HomeBottomText'),
  Canvas: assetColor('HomeCanvas'),
  Card: assetColor('HomeCard'),
  FeedbackFailure: assetColor('HomeFeedbackFailure'),
  FeedbackSuccess: assetColor('HomeFeedbackSuccess'),
  ImageBackground: assetColor('HomeImageBackground'),
  MarkBackground: assetColor('HomeMarkBackground'),
  NamedBodyText: assetColor('HomeNamedBodyText'),
  Outline: assetColor('HomeOutline'),
  Placeholder: assetColor('HomePlaceholder'),
  PrimaryText: assetColor('HomePrimaryText'),
  PrivacyText: assetColor('HomePrivacyText'),
  SecondaryText: assetColor('HomeSecondaryText'),
  Shadow: assetColor('HomeShadow'),
  SwitchOn: assetColor('HomeSwitchOn'),
  UnnamedText: assetColor('HomeUnnamedText'),
  SearchHighlight: assetColor('SearchHighlight'),
};
