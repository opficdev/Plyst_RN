package opfic.plyst.host.adapter.clip

import java.util.UUID

sealed interface ClipImageCleanupState {
  data object Completed : ClipImageCleanupState

  // 정리하지 못해 recoverPendingCleanup에서 다시 시도해야 하는 파일
  data class Pending(val fileID: UUID) : ClipImageCleanupState
}

data class ClipImageMutationResult<T>(
  val value: T,
  val cleanup: ClipImageCleanupState,
)
