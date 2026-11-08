package opfic.plyst.host.adapter.clip

import android.util.Log
import java.io.IOException
import java.util.UUID
import kotlin.coroutines.cancellation.CancellationException
import opfic.plyst.core.ClipImageFilesException
import opfic.plyst.core.ClipOperationException
import opfic.plyst.core.ClipStoreException

// 코어 오류의 기록과 어댑터 오류 변환
internal object ClipCoreFailure {
  private const val TAG = "ClipCoreAdapter"

  // 코어 오류를 어댑터 오류로 변환
  // 패닉은 호출별 대체 오류로 전달
  fun operationError(
    error: Exception,
    fallback: Exception,
  ): Exception {
    if (error is CancellationException || error is ClipImageFileError || error is ClipStorageError) return error
    if (error is ClipOperationException.Cancelled) return CancellationException()
    return when (error) {
      is ClipOperationException.CorruptedImage -> ClipImageFileError.CorruptedImage(UUID.fromString(error.fileId))
      is ClipOperationException.ClipboardWriteFailed -> fallback
      is ClipOperationException.Storage -> storageError(error.error, fallback)
      is ClipOperationException.Files -> imageFileError(error.error)
      is ClipStoreException -> storageError(error, fallback)
      is IOException -> ClipImageFileError.ReadFailed
      else -> fallback
    }
  }

  // 코어 저장소 오류를 어댑터 저장소 오류로 변환
  fun storageError(
    error: Exception,
    fallback: Exception,
  ): Exception =
    when (error) {
      is CancellationException, is ClipStorageError -> error
      is ClipStoreException.DuplicateId -> ClipStorageError.DuplicateID(UUID.fromString(error.id))
      is ClipStoreException.NotFound -> ClipStorageError.NotFound(UUID.fromString(error.id))
      is ClipStoreException.InvalidContent -> ClipStorageError.InvalidContent
      is ClipStoreException.ReadFailed -> ClipStorageError.ReadFailed
      is ClipStoreException.WriteFailed -> ClipStorageError.WriteFailed
      is ClipStoreException.CorruptedData -> ClipStorageError.CorruptedData
      else -> fallback
    }

  // 오류 설명에는 SQL과 저장값이 포함될 수 있어 종류와 코드만 기록
  fun log(
    error: Exception,
    operation: String,
  ) {
    when (error) {
      is CancellationException, is ClipOperationException.Cancelled -> Log.d(TAG, "$operation 취소")
      is ClipOperationException.Storage -> log(error.error, operation)
      is ClipOperationException.Files -> Log.e(TAG, "$operation 실패: ${error.error.javaClass.simpleName}")
      is ClipStoreException.ReadFailed -> Log.e(TAG, "$operation 실패: SQLite 코드 ${error.code}, 확장 코드 ${error.extendedCode}")
      is ClipStoreException.WriteFailed -> Log.e(TAG, "$operation 실패: SQLite 코드 ${error.code}, 확장 코드 ${error.extendedCode}")
      is ClipStoreException.CorruptedData -> Log.e(TAG, "$operation 실패: SQLite 코드 ${error.code}, 확장 코드 ${error.extendedCode}")
      else -> Log.e(TAG, "$operation 실패: ${error.javaClass.simpleName}")
    }
  }

  private fun imageFileError(error: ClipImageFilesException) =
    when (error) {
      is ClipImageFilesException.InvalidRoot -> ClipImageFileError.InvalidRoot
      is ClipImageFilesException.UnsafePath -> ClipImageFileError.UnsafePath
      is ClipImageFilesException.ReadFailed -> ClipImageFileError.ReadFailed
      is ClipImageFilesException.WriteFailed -> ClipImageFileError.WriteFailed
      is ClipImageFilesException.DeleteFailed -> ClipImageFileError.DeleteFailed
      is ClipImageFilesException.NotFound -> ClipImageFileError.NotFound(UUID.fromString(error.fileId))
      is ClipImageFilesException.SizeMismatch -> ClipImageFileError.CorruptedImage(UUID.fromString(error.fileId))
    }
}
