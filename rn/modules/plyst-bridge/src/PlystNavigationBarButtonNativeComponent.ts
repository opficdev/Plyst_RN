import type { HostComponent, ViewProps } from 'react-native';
import type {
  DirectEventHandler,
  WithDefault,
} from 'react-native/Libraries/Types/CodegenTypes';
import codegenNativeComponent from 'react-native/Libraries/Utilities/codegenNativeComponent';

export interface NativeProps extends ViewProps {
  // 항목을 놓을 쪽입니다. left나 right입니다.
  side: string;
  // 항목에 표시할 SF Symbol 이름입니다. 지정하면 title보다 우선합니다.
  icon?: string;
  // 지정하면 텍스트 항목으로 표시합니다.
  title?: string;
  isEnabled?: WithDefault<boolean, true>;
  onPress?: DirectEventHandler<Readonly<{}>>;
}

export default codegenNativeComponent<NativeProps>(
  'PlystNavigationBarButton',
) as HostComponent<NativeProps>;
