package opfic.plyst.host.service.clip.storage

import java.util.UUID
import kotlinx.coroutines.flow.Flow
import opfic.plyst.host.model.Clip
import opfic.plyst.host.model.ClipSortOrder
import opfic.plyst.host.model.ClipUpdate

// 클립의 텍스트와 메타데이터를 저장
// 이미지 바이트와 파일 생명주기는 별도 서비스에서 관리
// 구현체는 저장 확정과 이벤트 발행을 동일한 순서로 직렬화해야 함
// 쓰기 실패 시 기존 상태를 보존하고 이벤트를 발행하지 않아야 함
// 변경 사항이 없는 수정은 이벤트 발행 없이 현재 클립을 반환
// 저장 방식에 종속된 오류는 ClipStorageError로 매핑하고 CancellationException은 그대로 전파
interface ClipStorageService {
  // ClipSortOrder에서 정의한 결정적 순서로 반환
  suspend fun fetchAll(order: ClipSortOrder): List<Clip>

  // 해당 식별자가 존재하지 않으면 null을 반환
  suspend fun fetch(id: UUID): Clip?

  // 중복 식별자와 유효하지 않은 콘텐츠는 거부
  // 쓰기가 확정된 후에만 Inserted 이벤트를 발행
  suspend fun insert(clip: Clip)

  // 저장된 최신 스냅샷에 변경 사항을 적용하고 저장이 확정된 결과를 반환
  // 해당 식별자가 존재하지 않으면 NotFound를 던짐
  suspend fun update(
    id: UUID,
    change: ClipUpdate,
  ): Clip

  // 메타데이터를 제거하고 저장이 확정된 후 Deleted 이벤트를 발행
  // 해당 식별자가 존재하지 않으면 NotFound를 던짐
  // 호출부는 이미지 파일 서비스와 함께 이미지 원본 파일의 삭제를 조율
  suspend fun delete(id: UUID)

  // 수집을 시작한 뒤의 모든 변경을 저장 확정 순서로 전달
  // 버퍼 용량을 제한하지 않으며 초기 스냅샷 제공과 이전 변경의 재전달은 수행하지 않음
  fun changes(): Flow<ClipStorageEvent>
}
