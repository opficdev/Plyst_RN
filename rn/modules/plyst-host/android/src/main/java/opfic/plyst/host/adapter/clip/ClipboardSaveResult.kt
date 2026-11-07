package opfic.plyst.host.adapter.clip

import java.util.UUID
import opfic.plyst.host.model.Clip

sealed interface ClipboardSaveResult {
  data class Saved(val clip: Clip) : ClipboardSaveResult

  // 이미지 원본과 클립 기록은 저장됐지만 pending 표시 파일을 제거하지 못했음
  // recoverPendingCleanup()을 호출해야 정리를 다시 시도
  data class SavedWithPendingCleanup(
    val clip: Clip,
    val fileID: UUID,
  ) : ClipboardSaveResult

  data object Empty : ClipboardSaveResult

  data object Unsupported : ClipboardSaveResult

  data object AccessFailed : ClipboardSaveResult

  data object InvalidImage : ClipboardSaveResult
}
