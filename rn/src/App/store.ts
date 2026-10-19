import { createScreenStore } from '../Shared/State/screenStore';
import { navigationSlice } from './navigation';

// 이동 상태만 소유하므로 Service 호출이나 구독이 없고 Listener도 등록하지 않습니다.
export function createAppStore() {
  return createScreenStore({ slice: navigationSlice, start: () => {} });
}
