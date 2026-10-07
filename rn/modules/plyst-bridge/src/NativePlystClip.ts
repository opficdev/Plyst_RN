import type { TurboModule } from 'react-native';
import { TurboModuleRegistry } from 'react-native';

export type ClipImageRecord = {
  // 원본 이미지의 읽기 전용 file:// URI입니다.
  uri: string;
  // public.png와 같은 원본 타입 식별자입니다.
  contentType: string;
  pixelWidth: number;
  pixelHeight: number;
};

export type ClipRecord = {
  id: string;
  text: string | null;
  image: ClipImageRecord | null;
  name: string | null;
  memo: string | null;
  isPinned: boolean;
  // 날짜는 Unix epoch 기준 밀리초입니다. JavaScript Date와 같은 단위입니다.
  createdAt: number;
  lastUsedAt: number | null;
};

export interface Spec extends TurboModule {
  // 클립이 없으면 null입니다. 실패하면 E_INVALID_ID, E_UNAVAILABLE,
  // E_READ_FAILED, E_CORRUPTED_DATA, E_IMAGE_UNAVAILABLE 중 하나로 거부합니다.
  getClip(id: string): Promise<ClipRecord | null>;
}

export default TurboModuleRegistry.getEnforcing<Spec>('PlystClip');
