package opfic.plyst.host.service.clip.image

import java.util.UUID

sealed class ClipImageFileError : Exception() {
  data object InvalidRoot : ClipImageFileError()

  data object InvalidImage : ClipImageFileError()

  data object UnsupportedImage : ClipImageFileError()

  data class NotFound(val fileID: UUID) : ClipImageFileError()

  data class CorruptedImage(val fileID: UUID) : ClipImageFileError()

  data class NotImage(val clipID: UUID) : ClipImageFileError()

  data object UnsafePath : ClipImageFileError()

  data object ReadFailed : ClipImageFileError()

  data object WriteFailed : ClipImageFileError()

  data object DeleteFailed : ClipImageFileError()
}
