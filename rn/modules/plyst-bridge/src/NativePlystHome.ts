import type { CodegenTypes, TurboModule } from 'react-native';
import { TurboModuleRegistry } from 'react-native';

export interface Spec extends TurboModule {
  // JavaScript가 구독한 뒤 호출합니다. 보관된 저장 요청을 전달합니다. 무효화된 모듈은 무시합니다.
  ready(): void;
  // iPhone Duo이면 true입니다. 등록과 관계없으므로 ready() 전에도 호출할 수 있습니다.
  isDuoDevice(): boolean;
  // 호스트의 클립보드 저장 요청을 JavaScript에 전달합니다. ready() 이후에만 전송합니다.
  readonly onClipboardSaveRequest: CodegenTypes.EventEmitter<void>;
}

export default TurboModuleRegistry.getEnforcing<Spec>('PlystHome');
