import type { TurboModule } from 'react-native';
import { TurboModuleRegistry } from 'react-native';

export type CardRanges = {
  nameRanges: number[];
  bodyRanges: number[];
  excerptStart: number;
};

export interface Spec extends TurboModule {
  // 새 인덱스 핸들
  // 실패는 0
  createIndex(): number;
  // 작업 스레드 정지 신호 뒤 인덱스 해제
  freeIndex(handle: number): void;
  // order 전체와 바뀐 필드 반영
  // order에 없는 클립 삭제
  // positions는 order 안 위치
  // fields는 0 이름 1 본문 2 시간 0 3 시간 1
  // 미리 만들기는 시작하지 않음
  sync(handle: number, order: string[], positions: number[], fields: number[], texts: string[]): boolean;
  // 현재 order로 미리 만들기 시작
  // 이전 세대 중단
  prebuild(handle: number): boolean;
  cancelPrebuild(handle: number): void;
  // 일치한 order 위치의 오름차순 목록
  // 실패는 null
  filter(handle: number, query: string): number[] | null;
  // 이름과 본문 범위를 [location, length, ...]로 반환
  // 본문 범위가 없으면 excerptStart 0
  // isSynced는 name과 본문이 마지막으로 sync한 값과 같을 때 true
  // 실패는 null
  cardText(handle: number, id: string, name: string, body: string, query: string, isSynced: boolean): CardRanges | null;
}

export default TurboModuleRegistry.getEnforcing<Spec>('PlystSearch');
