import type { CodegenTypes, TurboModule } from 'react-native';
import { TurboModuleRegistry } from 'react-native';

export interface Spec extends TurboModule {
  // JavaScript가 구독한 뒤 호출함
  // 보관된 저장 요청을 전달함
  // 무효화된 모듈은 무시함
  ready(): void;
  // iPhone Duo이면 true
  // 등록과 관계없으므로 ready() 전에도 호출할 수 있음
  isDuoDevice(): boolean;
  // 호스트의 클립보드 저장 요청을 JavaScript에 전달함
  // ready() 이후에만 전송함
  readonly onClipboardSaveRequest: CodegenTypes.EventEmitter<void>;
}

export default TurboModuleRegistry.getEnforcing<Spec>('PlystHome');
