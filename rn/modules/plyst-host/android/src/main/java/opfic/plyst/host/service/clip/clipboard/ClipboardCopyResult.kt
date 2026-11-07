package opfic.plyst.host.service.clip.clipboard

import java.util.UUID
import opfic.plyst.host.model.Clip
import opfic.plyst.host.service.clip.storage.ClipStorageError

sealed interface ClipboardUsageUpdateFailure {
  data object Cancelled : ClipboardUsageUpdateFailure

  data class Storage(val error: ClipStorageError) : ClipboardUsageUpdateFailure

  // 같은 식별자가 다른 원본 또는 생성 시각의 클립으로 교체되어 사용 기록을 적용하지 않았음
  data object Replaced : ClipboardUsageUpdateFailure

  // 저장 서비스의 인터페이스에 포함되지 않은 오류
  // 원본 오류 내용은 노출하지 않음
  data object Unknown : ClipboardUsageUpdateFailure
}

sealed interface ClipboardCopyResult {
  // 클립보드 쓰기를 확인했고 사용 시각의 저장도 확정
  data class Copied(val clip: Clip) : ClipboardCopyResult

  data class WriteNotObserved(val id: UUID) : ClipboardCopyResult

  // 쓰기는 확인했지만 사용 시각을 저장하지 못했음
  // 자동으로 다시 복사하거나 되돌리지 않음
  data class CopiedWithoutLastUsedAt(
    val clip: Clip,
    val copiedAt: Long,
    val failure: ClipboardUsageUpdateFailure,
  ) : ClipboardCopyResult
}
