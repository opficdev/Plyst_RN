package opfic.plyst.host.model

import java.util.UUID

data class ClipImageMetadata(
  // 이미지 파일 서비스에서 해석하는 불투명 식별자
  // 경로나 파일 이름을 나타내지 않음
  val fileID: UUID,
  // public.png와 같은 통일된 타입 식별자
  val contentType: String,
  val pixelWidth: Int,
  val pixelHeight: Int,
  val byteCount: Int,
) {
  val isValid: Boolean
    get() = contentType.isNotBlank() && 0 < pixelWidth && 0 < pixelHeight && 0 < byteCount
}
