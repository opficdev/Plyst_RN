package opfic.plyst.host.model

import opfic.plyst.core.clipPinnedAt
import opfic.plyst.core.clipUsageApplies

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

  // 편집 초안을 저장할 때 최신 사용 시각을 덮어쓰지 않도록 사용 기록을 별도로 갱신
  // matching을 전달하면 식별자와 원본, 생성 시각이 같은 클립에만 적용
  data class LastUsedAt(
    val date: Long,
    val matching: Clip? = null,
  ) : ClipUpdate

  // 저장소의 직렬화된 쓰기 작업 내부에서 현재 저장된 최신 클립에 적용
  fun applying(clip: Clip): Clip =
    when (this) {
      is Details ->
        clip.copy(
          name = name,
          memo = memo,
          pinnedAt = clipPinnedAt(clip.pinnedAt?.referenceSeconds, isPinned, requestedAt.referenceSeconds)?.epochMilliseconds,
        )
      is LastUsedAt -> {
        val expected = matching
        if (expected != null && !clipUsageApplies(expected.coreIdentity, clip.coreIdentity)) {
          clip
        } else {
          clip.copy(lastUsedAt = date)
        }
      }
    }
}
