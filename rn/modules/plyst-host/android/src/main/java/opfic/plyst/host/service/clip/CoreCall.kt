package opfic.plyst.host.service.clip

import android.util.Log
import java.io.IOException
import java.util.UUID
import kotlin.coroutines.cancellation.CancellationException
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Job
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.job
import kotlinx.coroutines.withContext
import opfic.plyst.core.ClipCancellationSource
import opfic.plyst.core.ClipImageFilesException
import opfic.plyst.core.ClipOperationException
import opfic.plyst.core.ClipStoreException
import opfic.plyst.host.service.clip.image.ClipImageFileError
import opfic.plyst.host.service.clip.storage.ClipStorageError

private const val TAG = "ClipCoreCall"

// 호출한 코루틴의 취소 상태를 코어 판정 지점에 전달
private class JobCancellation(private val job: Job) : ClipCancellationSource {
  override fun isCancelled() = job.isCancelled
}

// 시작한 코어 호출은 끝까지 기다리고 확정된 결과를 취소로 바꾸지 않음
// withContext의 복귀 지점이 취소로 결과를 버리므로 NonCancellable로 감쌈
internal suspend fun <T> coreCall(
  dispatcher: CoroutineDispatcher,
  fallback: Exception,
  operation: (ClipCancellationSource) -> T,
): T {
  val job = currentCoroutineContext().job
  return withContext(NonCancellable) {
    withContext(dispatcher) {
      serviceErrors(fallback) { operation(JobCancellation(job)) }
    }
  }
}

// 코어 오류를 Service 오류로 변환
// 패닉은 호출별 대체 오류로 전달
internal inline fun <T> serviceErrors(
  fallback: Exception,
  operation: () -> T,
): T =
  try {
    operation()
  } catch (error: Exception) {
    throw serviceError(error, fallback)
  }

// 오류 설명에는 SQL과 저장값이 포함될 수 있어 종류만 기록
internal fun serviceError(
  error: Exception,
  fallback: Exception,
): Exception {
  if (error is CancellationException || error is ClipImageFileError || error is ClipStorageError) return error
  if (error is ClipOperationException.Cancelled) return CancellationException()
  Log.e(TAG, "코어 호출 실패: ${error.javaClass.simpleName}")
  return when (error) {
    is ClipOperationException.CorruptedImage -> ClipImageFileError.CorruptedImage(UUID.fromString(error.fileId))
    is ClipOperationException.ClipboardWriteFailed -> fallback
    is ClipOperationException.Storage -> storageError(error.error, fallback)
    is ClipOperationException.Files -> fileError(error.error)
    is ClipStoreException -> storageError(error, fallback)
    is IOException -> ClipImageFileError.ReadFailed
    else -> fallback
  }
}

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

private fun fileError(error: ClipImageFilesException) =
  when (error) {
    is ClipImageFilesException.InvalidRoot -> ClipImageFileError.InvalidRoot
    is ClipImageFilesException.UnsafePath -> ClipImageFileError.UnsafePath
    is ClipImageFilesException.ReadFailed -> ClipImageFileError.ReadFailed
    is ClipImageFilesException.WriteFailed -> ClipImageFileError.WriteFailed
    is ClipImageFilesException.DeleteFailed -> ClipImageFileError.DeleteFailed
    is ClipImageFilesException.NotFound -> ClipImageFileError.NotFound(UUID.fromString(error.fileId))
    is ClipImageFilesException.SizeMismatch -> ClipImageFileError.CorruptedImage(UUID.fromString(error.fileId))
  }
