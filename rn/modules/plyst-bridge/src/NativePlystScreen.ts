import type { CodegenTypes, TurboModule } from 'react-native';
import { TurboModuleRegistry } from 'react-native';

export interface Spec extends TurboModule {
  close(): void;
  // 호스트의 저장 버튼 활성 여부를 반영합니다.
  setSaveEnabled(isEnabled: boolean): void;
  // 호스트의 저장 버튼 탭을 값 없이 전달합니다.
  readonly onSave: CodegenTypes.EventEmitter<void>;
  // onSave 구독을 마친 뒤 저장 탭 수신 준비를 알립니다.
  ready(): void;
}

export default TurboModuleRegistry.getEnforcing<Spec>('PlystScreen');
