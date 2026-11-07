package opfic.plyst.host.service.clip

import java.util.UUID
import opfic.plyst.core.ClipStoreException
import opfic.plyst.host.service.clip.storage.ClipStorageError

internal fun storageError(
  error: ClipStoreException,
  fallback: Exception,
): Exception =
  when (error) {
    is ClipStoreException.DuplicateId -> ClipStorageError.DuplicateID(UUID.fromString(error.id))
    is ClipStoreException.NotFound -> ClipStorageError.NotFound(UUID.fromString(error.id))
    is ClipStoreException.InvalidContent -> ClipStorageError.InvalidContent
    is ClipStoreException.ReadFailed -> ClipStorageError.ReadFailed
    is ClipStoreException.WriteFailed -> ClipStorageError.WriteFailed
    is ClipStoreException.CorruptedData -> ClipStorageError.CorruptedData
    else -> fallback
  }
