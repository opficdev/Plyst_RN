package opfic.plyst.host.model

import java.net.URI

sealed interface ClipContent {
  // URL을 포함한 원본 문자열을 정규화하지 않고 저장
  data class Text(val text: String) : ClipContent

  data class Image(val image: ClipImageMetadata) : ClipContent

  // 앞뒤 공백을 제외한 전체가 공백 없는 단일 http 또는 https URL인지 여부
  // 화면에서 아이콘을 고를 때만 사용
  // 문장 안에 섞인 URL은 링크로 보지 않음
  val isWebLink: Boolean
    get() {
      if (this !is Text) return false
      val trimmed = text.trim()
      if (trimmed.isEmpty() || trimmed.any { it.isWhitespace() }) return false
      val uri = runCatching { URI(trimmed) }.getOrNull() ?: return false
      val scheme = uri.scheme?.lowercase() ?: return false
      return (scheme == "http" || scheme == "https") && !uri.host.isNullOrEmpty()
    }

  // 이미지의 메타데이터만 검증
  // 이미지 디코딩과 파일 존재 여부 검사는 이미지 파일 서비스의 책임
  val isValid: Boolean
    get() =
      when (this) {
        is Text -> text.isNotBlank()
        is Image -> image.isValid
      }
}
