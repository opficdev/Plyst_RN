package opfic.plyst.host.service.clip.storage

import java.util.UUID

sealed class ClipStorageError : Exception() {
  data class DuplicateID(val id: UUID) : ClipStorageError()

  data class NotFound(val id: UUID) : ClipStorageError()

  data object InvalidContent : ClipStorageError()

  data object ReadFailed : ClipStorageError()

  data object WriteFailed : ClipStorageError()

  data object CorruptedData : ClipStorageError()
}
