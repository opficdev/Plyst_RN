package opfic.plyst.host.service.clip.clipboard

sealed interface ClipboardWriteContent {
  data class Text(val text: String) : ClipboardWriteContent

  class Image(
    val data: ByteArray,
    val contentType: String,
  ) : ClipboardWriteContent
}

enum class ClipboardWriteResult {
  OBSERVED,
  NOT_OBSERVED,
}

interface ClipboardWriter {
  suspend fun write(content: ClipboardWriteContent): ClipboardWriteResult
}
