import type { HostComponent, ViewProps } from 'react-native';
import type {
  DirectEventHandler,
  WithDefault,
} from 'react-native/Libraries/Types/CodegenTypes';
import codegenNativeComponent from 'react-native/Libraries/Utilities/codegenNativeComponent';

export interface NativeProps extends ViewProps {
  // SF Symbol 이름
  // 지정하면 원형 아이콘 버튼으로 표시함
  icon?: string;
  // 지정하면 캡슐형 텍스트 버튼으로 표시함
  // icon과 title 중 하나만 지정함
  title?: string;
  isEnabled?: WithDefault<boolean, true>;
  onPress?: DirectEventHandler<Readonly<{}>>;
}

export default codegenNativeComponent<NativeProps>(
  'PlystDetailBarButton',
) as HostComponent<NativeProps>;
