package opfic.plyst.host.service.clip.clipboard

import java.util.UUID
import opfic.plyst.host.model.Clip

sealed interface ClipboardCopyResult {
  // 클립보드 쓰기를 확인했고 사용 시각의 저장도 확정했음
  data class Copied(val clip: Clip) : ClipboardCopyResult

  data class WriteNotObserved(val id: UUID) : ClipboardCopyResult

  // 쓰기는 확인했지만 사용 시각을 저장하지 못했음
  // 자동으로 다시 복사하거나 되돌리지 않음
  data class CopiedWithoutLastUsedAt(
    val clip: Clip,
    val copiedAt: Long,
  ) : ClipboardCopyResult
}
