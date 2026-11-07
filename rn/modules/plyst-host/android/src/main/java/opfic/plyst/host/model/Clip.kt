package opfic.plyst.host.model

import java.util.UUID
import opfic.plyst.core.ClipContentValue
import opfic.plyst.core.ClipValue

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

internal val Clip.coreValue: ClipValue
  get() =
    ClipValue(
      id = id.toString().uppercase(),
      content = content.coreValue,
      name = name?.wellFormed,
      pinnedAt = pinnedAt?.referenceSeconds,
      memo = memo?.wellFormed,
      createdAt = createdAt.referenceSeconds,
      lastUsedAt = lastUsedAt?.referenceSeconds,
    )

// 식별자가 UUID 형식이 아니면 null
internal val ClipValue.clip: Clip?
  get() {
    val id = id.uuid ?: return null
    val content =
      when (val content = content) {
        is ClipContentValue.Text -> ClipContent.Text(content.text)
        is ClipContentValue.Image ->
          ClipContent.Image(
            ClipImageMetadata(
              fileID = content.fileId.uuid ?: return null,
              contentType = content.contentType,
              pixelWidth = content.pixelWidth.toInt(),
              pixelHeight = content.pixelHeight.toInt(),
              byteCount = content.byteCount.toInt(),
            ),
          )
      }
    return Clip(
      id = id,
      content = content,
      name = name,
      pinnedAt = pinnedAt?.epochMilliseconds,
      memo = memo,
      createdAt = createdAt.epochMilliseconds,
      lastUsedAt = lastUsedAt?.epochMilliseconds,
    )
  }

internal val String.uuid: UUID?
  get() = runCatching { UUID.fromString(this) }.getOrNull()
