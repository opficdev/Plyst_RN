import type { CodegenTypes, TurboModule } from 'react-native';
import { TurboModuleRegistry } from 'react-native';

// 네이티브 호스트가 관리하는 검색 화면의 표시 상태입니다.
export type SearchVisibilityChange = {
  // 호스트가 검색 화면을 열면 true를 전달하고 닫으면 false를 전달합니다.
  isVisible: boolean;
};

export interface Spec extends TurboModule {
  // JavaScript가 상세 화면을 요청합니다. 잘못된 UUID나 text, image 이외의 종류는 무시합니다.
  openClip(id: string, kind: string): void;
  // JavaScript가 검색 화면을 요청합니다. 등록된 호스트가 없으면 무시합니다.
  openSearch(): void;
  // JavaScript가 구독한 뒤 호출합니다. 현재 상태를 한 번 전달하며 무효화된 모듈은 무시합니다.
  ready(): void;
  // 호스트의 검색 표시 상태를 JavaScript에 전달합니다. ready() 이후에만 전송합니다.
  readonly onSearchVisibilityChange: CodegenTypes.EventEmitter<SearchVisibilityChange>;
}

export default TurboModuleRegistry.getEnforcing<Spec>('PlystHome');
