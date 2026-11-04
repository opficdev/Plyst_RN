package opfic.plyst.host.service.clip.clipboard

sealed interface ClipboardReadResult {
  data class Text(val text: String) : ClipboardReadResult

  class Image(val data: ByteArray) : ClipboardReadResult

  data object Empty : ClipboardReadResult

  data object Unsupported : ClipboardReadResult

  data object AccessFailed : ClipboardReadResult
}

interface ClipboardReader {
  suspend fun read(): ClipboardReadResult
}
