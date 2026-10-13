import type { CodegenTypes, TurboModule } from 'react-native';
import { TurboModuleRegistry } from 'react-native';

export type ClipImageRecord = {
  // 원본 이미지의 바이트 수입니다.
  byteCount: number;
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
  // Foundation URL 검증 결과입니다. 이미지 클립은 false입니다.
  isWebLink: boolean;
  // 날짜는 Unix epoch 기준 밀리초입니다. JavaScript Date와 같은 단위입니다.
  createdAt: number;
  lastUsedAt: number | null;
};

export type ClipChange = {
  // kind는 inserted, updated, deleted 중 하나입니다.
  kind: string;
  id: string;
};

export interface Spec extends TurboModule {
  readonly onClipChange: CodegenTypes.EventEmitter<ClipChange>;
  ready(): void;
  // 클립이 없으면 null입니다. 실패하면 E_INVALID_ID, E_UNAVAILABLE,
  // E_READ_FAILED, E_CORRUPTED_DATA 중 하나로 거부합니다.
  getClip(id: string): Promise<ClipRecord | null>;
  // 페이지 구분 없이 전체 클립을 생성 시각 내림차순으로 반환합니다. 동률이면 id.uuidString 오름차순입니다.
  // 실패하면 E_UNAVAILABLE, E_READ_FAILED, E_CORRUPTED_DATA 중 하나로 거부합니다.
  getClips(): Promise<ClipRecord[]>;
  // 실패하면 E_UNAVAILABLE, E_READ_FAILED, E_CORRUPTED_DATA 중 하나로 거부합니다.
  getSearchHistory(): Promise<string[]>;
  // Swift가 정규화한 뒤 저장한 목록입니다. 공백뿐이면 쓰지 않고 null을 반환합니다.
  // 실패하면 E_UNAVAILABLE, E_WRITE_FAILED, E_CORRUPTED_DATA 중 하나로 거부합니다.
  recordSearchTerm(term: string): Promise<string[] | null>;
  // 없거나 공백뿐인 검색어는 현재 목록을 반환합니다.
  // 실패하면 E_UNAVAILABLE, E_WRITE_FAILED, E_CORRUPTED_DATA 중 하나로 거부합니다.
  removeSearchTerm(term: string): Promise<string[]>;
  // 저장값을 해석하지 않고 삭제합니다. 실패하면 E_UNAVAILABLE, E_WRITE_FAILED 중 하나로 거부합니다.
  removeAllSearchTerms(): Promise<void>;
  // 결과는 saved, empty, unsupported, accessFailed, invalidImage 중 하나입니다.
  // 실패하면 E_UNAVAILABLE, E_SAVE_FAILED 중 하나로 거부합니다.
  saveCurrentClipboard(): Promise<string>;
  // 매번 다시 만든 미리보기의 file:// URI입니다. 클립이 없거나 이미지가 아니면 null입니다.
  // 실패하면 E_INVALID_ID, E_UNAVAILABLE, E_IMAGE_UNAVAILABLE 중 하나로 거부합니다.
  getClipImagePreview(id: string): Promise<string | null>;
  // 매 호출마다 다시 쓰는 <fileID>/thumbnail-<px> 파일의 file:// URI입니다.
  // 호출자가 크기를 선택하며 크기마다 별도 파일을 사용합니다. 클립이 없거나 이미지가 아니면 null입니다.
  // 크기 인자 없이 고정 크기를 사용하는 getClipImagePreview와 다릅니다.
  // 실패하면 E_INVALID_ID, E_UNAVAILABLE, E_IMAGE_UNAVAILABLE 중 하나로 거부합니다.
  getClipThumbnail(
    id: string,
    maximumPixelDimension: number,
  ): Promise<string | null>;
  // 결과는 saved, denied, restricted 중 하나입니다. 클립이 없으면 null입니다.
  // 실패하면 E_INVALID_ID, E_UNAVAILABLE, E_PHOTO_SAVE_FAILED 중 하나로 거부합니다.
  saveClipImageToPhotos(id: string): Promise<string | null>;
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
