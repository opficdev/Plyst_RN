package opfic.plyst.host.service.clip.clipboard

import java.util.UUID
import kotlin.coroutines.cancellation.CancellationException
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import opfic.plyst.host.model.Clip
import opfic.plyst.host.model.ClipContent
import opfic.plyst.host.model.ClipUpdate
import opfic.plyst.host.service.clip.image.ClipImageCleanupState
import opfic.plyst.host.service.clip.image.ClipImageFileError
import opfic.plyst.host.service.clip.image.ClipImageService
import opfic.plyst.host.service.clip.storage.ClipStorageError
import opfic.plyst.host.service.clip.storage.ClipStorageService

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
// storage와 images는 같은 저장소를 사용해야 함
class ClipboardService(
  private val storage: ClipStorageService,
  private val images: ClipImageService,
  private val reader: ClipboardReader,
  private val writer: ClipboardWriter,
) {
  // 저장과 복사 작업 전체를 요청 순서대로 처리
  private val mutex = Mutex()

  // 저장소 오류와 CancellationException은 그대로 전파
  // 저장 확정 이후에는 취소를 다시 확인하지 않음
  suspend fun saveCurrentClipboard(): ClipboardSaveResult =
    mutex.withLock {
      when (val result = reader.read()) {
        is ClipboardReadResult.Text -> {
          val content = ClipContent.Text(result.text)
          if (!content.isValid) return@withLock ClipboardSaveResult.Empty
          currentCoroutineContext().ensureActive()
          val clip = Clip(content = content)
          storage.insert(clip)
          ClipboardSaveResult.Saved(clip)
        }
        is ClipboardReadResult.Image -> {
          currentCoroutineContext().ensureActive()
          try {
            val saved = images.saveImage(result.data)
            when (val cleanup = saved.cleanup) {
              ClipImageCleanupState.Completed -> ClipboardSaveResult.Saved(saved.value)
              is ClipImageCleanupState.Pending -> ClipboardSaveResult.SavedWithPendingCleanup(saved.value, cleanup.fileID)
            }
          } catch (error: ClipImageFileError.InvalidImage) {
            ClipboardSaveResult.InvalidImage
          } catch (error: ClipImageFileError.UnsupportedImage) {
            ClipboardSaveResult.Unsupported
          }
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
      val clip = storage.fetch(id) ?: throw ClipStorageError.NotFound(id)
      val content =
        when (val value = clip.content) {
          is ClipContent.Text -> ClipboardWriteContent.Text(value.text)
          // 같은 클립 식별자가 재사용돼도 최초 조회한 메타데이터와 다른 원본을 섞지 않음
          is ClipContent.Image -> ClipboardWriteContent.Image(images.loadImage(value.image), value.image.contentType)
        }
      currentCoroutineContext().ensureActive()
      if (writer.write(content) != ClipboardWriteResult.OBSERVED) return@withLock ClipboardCopyResult.WriteNotObserved(id)
      val copiedAt = System.currentTimeMillis()
      try {
        val updated = storage.update(id, ClipUpdate.LastUsedAt(copiedAt, matching = clip))
        if (updated.id != clip.id || updated.content != clip.content || updated.createdAt != clip.createdAt) {
          ClipboardCopyResult.CopiedWithoutLastUsedAt(clip, copiedAt)
        } else {
          // 갱신 확정 뒤 발생한 취소로 완료된 복사와 사용 기록을 숨기지 않음
          ClipboardCopyResult.Copied(updated)
        }
      } catch (error: CancellationException) {
        ClipboardCopyResult.CopiedWithoutLastUsedAt(clip, copiedAt)
      } catch (error: Exception) {
        ClipboardCopyResult.CopiedWithoutLastUsedAt(clip, copiedAt)
      }
    }
}
