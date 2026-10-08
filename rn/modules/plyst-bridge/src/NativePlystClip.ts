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
  // Swift String.count로 센 글자 수입니다. 이미지 클립은 0입니다.
  characterCount: number;
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
  // 저장이 확정된 클립을 반환합니다. 클립이 없으면 null입니다.
  // 실패하면 E_INVALID_ID, E_UNAVAILABLE, E_WRITE_FAILED, E_CORRUPTED_DATA 중 하나로 거부합니다.
  updateClip(
    id: string,
    name: string | null,
    memo: string | null,
    isPinned: boolean,
  ): Promise<ClipRecord | null>;
  // 삭제했거나 이미 없으면 반환값 없이 성공합니다.
  // 실패하면 E_INVALID_ID, E_UNAVAILABLE, E_WRITE_FAILED, E_CORRUPTED_DATA 중 하나로 거부합니다.
  deleteClip(id: string): Promise<void>;
  // 복사 결과는 copied, copiedWithoutLastUsedAt, writeNotObserved 중 하나입니다. 클립이 없으면 null입니다.
  // 실패하면 E_INVALID_ID, E_UNAVAILABLE, E_COPY_FAILED 중 하나로 거부합니다.
  copyClip(id: string): Promise<string | null>;
}

export default TurboModuleRegistry.getEnforcing<Spec>('PlystClip');
