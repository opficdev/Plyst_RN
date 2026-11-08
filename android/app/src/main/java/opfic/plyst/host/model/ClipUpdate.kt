package opfic.plyst.host.model

import opfic.plyst.core.ClipUpdateValue

sealed interface ClipUpdate {
  // 편집 가능한 상세 정보를 한 번에 교체
  // null은 대응하는 필드의 값을 제거하는 의미
  // 새로 고정하면 요청 시각을 기록
  // 이미 고정되어 있으면 기존 고정 시각을 유지하고 해제하면 제거
  data class Details(
    val name: String?,
    val memo: String?,
    val isPinned: Boolean,
    val requestedAt: Long,
  ) : ClipUpdate
}

internal val ClipUpdate.coreValue: ClipUpdateValue
  get() =
    when (this) {
      is ClipUpdate.Details -> ClipUpdateValue.Details(name?.wellFormed, memo?.wellFormed, isPinned, requestedAt.referenceSeconds)
    }
