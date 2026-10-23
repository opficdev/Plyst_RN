import type { HostComponent, ViewProps } from 'react-native';
import type {
  DirectEventHandler,
  WithDefault,
} from 'react-native/Libraries/Types/CodegenTypes';
import codegenNativeComponent from 'react-native/Libraries/Utilities/codegenNativeComponent';

export interface NativeProps extends ViewProps {
  // fadeIn은 투명에서 불투명으로, fadeOut은 불투명에서 투명으로 바꿉니다.
  // expand는 fadeIn과 함께 오른쪽 끝을 고정한 채 너비를 0에서 늘립니다.
  effect: string;
  // true가 되면 나타나는 애니메이션을, false가 되면 사라지는 애니메이션을 시작합니다.
  isPresented?: WithDefault<boolean, false>;
  onTransitionEnd?: DirectEventHandler<Readonly<{ isPresented: boolean }>>;
}

export default codegenNativeComponent<NativeProps>(
  'PlystSearchTransition',
) as HostComponent<NativeProps>;
