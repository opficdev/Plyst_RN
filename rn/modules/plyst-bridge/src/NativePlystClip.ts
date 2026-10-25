import type { CodegenTypes, TurboModule } from 'react-native';
import { TurboModuleRegistry } from 'react-native';

export type ClipImageRecord = {
  // 원본 이미지의 바이트 수
  byteCount: number;
  // public.png와 같은 원본 타입 식별자
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
  // 고정한 시각이며 단위는 createdAt과 같은 epoch 밀리초이고 고정하지 않았으면 null
  pinnedAt: number | null;
  // Foundation URL 검증 결과
  // 이미지 클립은 false
  isWebLink: boolean;
  // 날짜는 Unix epoch 기준 밀리초
  // JavaScript Date와 같은 단위
  createdAt: number;
  lastUsedAt: number | null;
};

export type ClipChange = {
  // kind는 inserted, updated, deleted 중 하나
  kind: string;
  id: string;
};

export interface Spec extends TurboModule {
  readonly onClipChange: CodegenTypes.EventEmitter<ClipChange>;
  ready(): void;
  // 클립이 없으면 null
  // 실패하면 E_INVALID_ID, E_UNAVAILABLE,
  // E_READ_FAILED, E_CORRUPTED_DATA 중 하나로 거부함
  getClip(id: string): Promise<ClipRecord | null>;
  // 페이지 구분 없이 전체 클립을 생성 시각 내림차순으로 반환함
  // 동률이면 id.uuidString 오름차순
  // 실패하면 E_UNAVAILABLE, E_READ_FAILED, E_CORRUPTED_DATA 중 하나로 거부함
  getClips(): Promise<ClipRecord[]>;
  // 실패하면 E_UNAVAILABLE, E_READ_FAILED, E_CORRUPTED_DATA 중 하나로 거부함
  getSearchHistory(): Promise<string[]>;
  // Swift가 정규화한 뒤 저장한 목록
  // 공백뿐이면 쓰지 않고 null을 반환함
  // 실패하면 E_UNAVAILABLE, E_WRITE_FAILED, E_CORRUPTED_DATA 중 하나로 거부함
  recordSearchTerm(term: string): Promise<string[] | null>;
  // 없거나 공백뿐인 검색어는 현재 목록을 반환함
  // 실패하면 E_UNAVAILABLE, E_WRITE_FAILED, E_CORRUPTED_DATA 중 하나로 거부함
  removeSearchTerm(term: string): Promise<string[]>;
  // 저장값을 해석하지 않고 삭제함
  // 실패하면 E_UNAVAILABLE, E_WRITE_FAILED 중 하나로 거부함
  removeAllSearchTerms(): Promise<void>;
  // 결과는 saved, empty, unsupported, accessFailed, invalidImage 중 하나
  // 실패하면 E_UNAVAILABLE, E_SAVE_FAILED 중 하나로 거부함
  saveCurrentClipboard(): Promise<string>;
  // 매번 다시 만든 미리보기의 file:// URI
  // 클립이 없거나 이미지가 아니면 null
  // 실패하면 E_INVALID_ID, E_UNAVAILABLE, E_IMAGE_UNAVAILABLE 중 하나로 거부함
  getClipImagePreview(id: string): Promise<string | null>;
  // 매 호출마다 다시 쓰는 <fileID>/thumbnail-<px> 파일의 file:// URI
  // 호출자가 크기를 선택하며 크기마다 별도 파일을 사용함
  // 클립이 없거나 이미지가 아니면 null
  // 크기 인자 없이 고정 크기를 사용하는 getClipImagePreview와 다름
  // 실패하면 E_INVALID_ID, E_UNAVAILABLE, E_IMAGE_UNAVAILABLE 중 하나로 거부함
  getClipThumbnail(
    id: string,
    maximumPixelDimension: number,
  ): Promise<string | null>;
  // 결과는 saved, denied, restricted 중 하나
  // 클립이 없으면 null
  // 실패하면 E_INVALID_ID, E_UNAVAILABLE, E_PHOTO_SAVE_FAILED 중 하나로 거부함
  saveClipImageToPhotos(id: string): Promise<string | null>;
  // 저장이 확정된 클립을 반환함
  // 클립이 없으면 null
  // 실패하면 E_INVALID_ID, E_UNAVAILABLE, E_WRITE_FAILED, E_CORRUPTED_DATA 중 하나로 거부함
  updateClip(
    id: string,
    name: string | null,
    memo: string | null,
    isPinned: boolean,
  ): Promise<ClipRecord | null>;
  // 삭제했거나 이미 없으면 반환값 없이 성공함
  // 실패하면 E_INVALID_ID, E_UNAVAILABLE, E_WRITE_FAILED, E_CORRUPTED_DATA 중 하나로 거부함
  deleteClip(id: string): Promise<void>;
  // 복사 결과는 copied, copiedWithoutLastUsedAt, writeNotObserved 중 하나
  // 클립이 없으면 null
  // 실패하면 E_INVALID_ID, E_UNAVAILABLE, E_COPY_FAILED 중 하나로 거부함
  copyClip(id: string): Promise<string | null>;
}

export default TurboModuleRegistry.getEnforcing<Spec>('PlystClip');
