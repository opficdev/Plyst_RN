package opfic.plyst.host.model

import java.util.UUID

// 저장된 클립의 불변 스냅샷
// 추가 이후 콘텐츠와 생성 시각은 변경되지 않음
// 시각은 Unix epoch 밀리초
data class Clip(
  val id: UUID = UUID.randomUUID(),
  val content: ClipContent,
  val name: String? = null,
  val pinnedAt: Long? = null,
  val memo: String? = null,
  val createdAt: Long = System.currentTimeMillis(),
  // 클립을 다시 복사하는 작업이 성공하기 전까지는 null
  val lastUsedAt: Long? = null,
)
