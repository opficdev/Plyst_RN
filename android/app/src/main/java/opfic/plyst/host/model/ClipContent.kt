package opfic.plyst.host.model

import opfic.plyst.core.ClipContentValue
import opfic.plyst.core.clipImageIsValid
import opfic.plyst.core.clipTextIsValid
import opfic.plyst.core.clipTextIsWebLink

sealed interface ClipContent {
  // URL을 포함한 원본 문자열을 정규화하지 않고 저장
  data class Text(val text: String) : ClipContent

  data class Image(val image: ClipImageMetadata) : ClipContent

  // 앞뒤 공백을 제외한 전체가 공백 없는 단일 http 또는 https URL인지 여부
  // 화면에서 아이콘을 고를 때만 사용
  // 문장 안에 섞인 URL은 링크로 보지 않음
  val isWebLink: Boolean
    get() = this is Text && clipTextIsWebLink(text.wellFormed)

  // 이미지의 메타데이터만 검증
  // 이미지 디코딩과 파일 존재 여부 검사는 ClipCoreAdapter의 책임
  val isValid: Boolean
    get() =
      when (this) {
        is Text -> clipTextIsValid(text.wellFormed)
        is Image ->
          clipImageIsValid(
            image.contentType.wellFormed,
            image.pixelWidth.toLong(),
            image.pixelHeight.toLong(),
            image.byteCount.toLong(),
          )
      }
}

internal val ClipContent.coreValue: ClipContentValue
  get() =
    when (this) {
      is ClipContent.Text -> ClipContentValue.Text(text.wellFormed)
      is ClipContent.Image ->
        ClipContentValue.Image(
          image.fileID.toString().uppercase(),
          image.contentType.wellFormed,
          image.pixelWidth.toLong(),
          image.pixelHeight.toLong(),
          image.byteCount.toLong(),
        )
    }
