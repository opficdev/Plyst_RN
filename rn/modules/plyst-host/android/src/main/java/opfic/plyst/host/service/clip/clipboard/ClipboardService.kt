package opfic.plyst.host.service.clip.clipboard

import java.util.UUID
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import opfic.plyst.core.ClipboardCopyValue
import opfic.plyst.core.ClipboardOperations
import opfic.plyst.core.ClipboardSaveValue
import opfic.plyst.core.ClipboardUsageFailureValue
import opfic.plyst.core.ClipboardWriting
import opfic.plyst.core.ClipValue
import opfic.plyst.host.model.Clip
import opfic.plyst.host.model.clip
import opfic.plyst.host.model.epochMilliseconds
import opfic.plyst.host.model.wellFormed
import opfic.plyst.host.service.clip.coreCall
import opfic.plyst.host.service.clip.image.ClipImageCodec
import opfic.plyst.host.service.clip.image.ClipImageFileError
import opfic.plyst.host.service.clip.image.ClipImageService
import opfic.plyst.host.service.clip.storage.ClipStorageError
import opfic.plyst.host.service.clip.storageError

sealed interface ClipboardSaveResult {
  data class Saved(val clip: Clip) : ClipboardSaveResult

  // 이미지 원본과 클립 기록은 저장됐지만 pending 표시 파일을 제거하지 못했음
  // recoverPendingCleanup()을 호출해야 정리를 다시 시도
  data class SavedWithPendingCleanup(
    val clip: Clip,
    val fileID: UUID,
  ) : ClipboardSaveResult

  data object Empty : ClipboardSaveResult

  data object Unsupported : ClipboardSaveResult

  data object AccessFailed : ClipboardSaveResult

  data object InvalidImage : ClipboardSaveResult
}

// 사용자 요청에 따라 클립을 저장하거나 다시 복사
// 구성 시에는 클립보드에 접근하지 않음
// 순서와 결과 판정은 코어의 ClipboardOperations가 맡고 이 타입은 읽기, 실행 위치, 값 변환을 담당
class ClipboardService(
  private val images: ClipImageService,
  private val reader: ClipboardReader,
  writer: ClipboardWriting,
) {
  private val core = ClipboardOperations(images.core, writer)

  // 저장과 복사 작업 전체를 요청 순서대로 처리
  private val mutex = Mutex()

  // 저장소 오류와 CancellationException은 그대로 전파
  // 저장 확정 이후에는 취소를 다시 확인하지 않음
  suspend fun saveCurrentClipboard(): ClipboardSaveResult =
    mutex.withLock {
      when (val result = reader.read()) {
        is ClipboardReadResult.Text ->
          saveResult(coreCall(Dispatchers.IO, ClipStorageError.WriteFailed) { core.saveText(result.text.wellFormed, it) })
        is ClipboardReadResult.Image ->
          try {
            val saved =
              coreCall(Dispatchers.IO, ClipImageFileError.WriteFailed) { cancellation ->
                val properties = ClipImageCodec.validated(result.data)
                images.withDirectBuffer(result.data) { core.saveImage(it, properties, cancellation) }
              }
            saveResult(saved)
          } catch (error: ClipImageFileError.InvalidImage) {
            ClipboardSaveResult.InvalidImage
          } catch (error: ClipImageFileError.UnsupportedImage) {
            ClipboardSaveResult.Unsupported
          }
        ClipboardReadResult.Empty -> ClipboardSaveResult.Empty
        ClipboardReadResult.Unsupported -> ClipboardSaveResult.Unsupported
        ClipboardReadResult.AccessFailed -> ClipboardSaveResult.AccessFailed
      }
    }

  // 쓰기 전 오류는 전파
  // 쓰기가 확인된 이후의 사용 시각 저장 실패는 부분 성공으로 반환
  suspend fun copy(id: UUID): ClipboardCopyResult =
    mutex.withLock {
      val copied = coreCall(Dispatchers.IO, ClipImageFileError.ReadFailed) { core.copy(id.toString().uppercase(), it) }
      when (copied) {
        is ClipboardCopyValue.Copied -> ClipboardCopyResult.Copied(clip(copied.clip))
        is ClipboardCopyValue.WriteNotObserved -> ClipboardCopyResult.WriteNotObserved(id)
        is ClipboardCopyValue.CopiedWithoutLastUsedAt ->
          ClipboardCopyResult.CopiedWithoutLastUsedAt(clip(copied.clip), copied.copiedAt.epochMilliseconds, failure(copied.failure))
      }
    }

  private fun saveResult(value: ClipboardSaveValue) =
    when (value) {
      is ClipboardSaveValue.Saved -> ClipboardSaveResult.Saved(clip(value.clip))
      is ClipboardSaveValue.SavedWithPendingCleanup ->
        ClipboardSaveResult.SavedWithPendingCleanup(clip(value.clip), UUID.fromString(value.fileId))
      ClipboardSaveValue.Empty -> ClipboardSaveResult.Empty
    }

  private fun failure(value: ClipboardUsageFailureValue) =
    when (value) {
      ClipboardUsageFailureValue.Cancelled -> ClipboardUsageUpdateFailure.Cancelled
      is ClipboardUsageFailureValue.Storage ->
        (storageError(value.error, ClipStorageError.WriteFailed) as? ClipStorageError)
          ?.let(ClipboardUsageUpdateFailure::Storage)
          ?: ClipboardUsageUpdateFailure.Unknown
      ClipboardUsageFailureValue.Replaced -> ClipboardUsageUpdateFailure.Replaced
      ClipboardUsageFailureValue.Unknown -> ClipboardUsageUpdateFailure.Unknown
    }

  // 코어가 검사한 식별자라 변환은 실패하지 않음
  private fun clip(value: ClipValue): Clip = value.clip ?: throw ClipStorageError.CorruptedData
}
