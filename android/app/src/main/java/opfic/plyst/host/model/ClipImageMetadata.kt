package opfic.plyst.host.model

import java.util.UUID
import opfic.plyst.core.ClipImageValue

data class ClipImageMetadata(
  // 코어가 해석하는 불투명 식별자
  // 경로나 파일 이름을 나타내지 않음
  val fileID: UUID,
  // public.png와 같은 통일된 타입 식별자
  val contentType: String,
  val pixelWidth: Int,
  val pixelHeight: Int,
  val byteCount: Int,
)

internal val ClipImageMetadata.coreValue: ClipImageValue
  get() = ClipImageValue(fileID.toString().uppercase(), contentType, pixelWidth.toLong(), pixelHeight.toLong(), byteCount.toLong())
