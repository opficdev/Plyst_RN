package opfic.plyst.host.service.clip.image

import java.io.File
import java.util.UUID
import kotlin.coroutines.cancellation.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import opfic.plyst.host.model.Clip
import opfic.plyst.host.model.ClipContent
import opfic.plyst.host.model.ClipImageMetadata
import opfic.plyst.host.model.ClipSortOrder
import opfic.plyst.host.service.clip.storage.ClipStorageError
import opfic.plyst.host.service.clip.storage.ClipStorageService

// 같은 루트의 이미지 쓰기와 복구를 하나의 인스턴스에서 조율
// 미리보기와 썸네일은 원본에서 다시 만들 수 있는 파생 파일
class ClipImageService(
  private val storage: ClipStorageService,
  private val files: ClipImageFileStore,
) {
  // 저장소 호출을 포함한 작업 전체를 요청 순서대로 처리
  private val mutex = Mutex()

  suspend fun saveImage(
    data: ByteArray,
    id: UUID = UUID.randomUUID(),
    createdAt: Long = System.currentTimeMillis(),
  ): ClipImageMutationResult<Clip> =
    serialized {
      val image = io { files.save(data) }
      val clip = Clip(id = id, content = ClipContent.Image(image), createdAt = createdAt)
      try {
        storage.insert(clip)
      } catch (error: Exception) {
        io { runCatching { files.delete(image.fileID) } }
        throw error
      }
      val cleanup =
        try {
          io { files.finishPending(image.fileID) }
          ClipImageCleanupState.Completed
        } catch (error: ClipImageFileError) {
          ClipImageCleanupState.Pending(image.fileID)
        }
      ClipImageMutationResult(clip, cleanup)
    }

  // 클립을 재조회하지 않고 전달받은 메타데이터에 대응하는 원본을 검증
  suspend fun loadImage(image: ClipImageMetadata): ByteArray = serialized { io { files.load(image) } }

  // 삭제와 직렬화하여 원본에서 미리보기 파일을 매번 다시 만듦
  suspend fun makePreviewFile(image: ClipImageMetadata): File =
    serialized { io { files.writePreview(image, PREVIEW_PIXEL_DIMENSION) } }

  // 삭제와 직렬화하여 요청한 크기의 썸네일 파일을 매번 다시 만듦
  suspend fun makeThumbnailFile(
    image: ClipImageMetadata,
    maximumPixelDimension: Int,
  ): File = serialized { io { files.writeThumbnail(image, maximumPixelDimension) } }

  // DB 삭제 확정 후 파일 정리에 실패해도 확정된 삭제를 실패로 반환하지 않음
  suspend fun delete(id: UUID): ClipImageMutationResult<UUID> =
    serialized {
      val clip = storage.fetch(id) ?: throw ClipStorageError.NotFound(id)
      val image = (clip.content as? ClipContent.Image)?.image
      if (image != null) io { files.markPending(image.fileID) }
      storage.delete(id)
      val cleanup = if (image == null) ClipImageCleanupState.Completed else clean(image.fileID)
      ClipImageMutationResult(id, cleanup)
    }

  // 구성 이후 명시적으로 호출
  // 이번에 정리하지 못한 fileID만 반환
  // DB 조회에 실패하면 후보를 변경하지 않고 오류를 던짐
  suspend fun recoverPendingCleanup(): List<UUID> =
    serialized {
      val candidates = io { files.pendingFileIDs() }
      if (candidates.isEmpty()) return@serialized emptyList()
      val references = imageReferences()
      candidates.filter { fileID ->
        try {
          io { clean(fileID, fileID in references) }
          false
        } catch (error: CancellationException) {
          throw error
        } catch (error: Exception) {
          true
        }
      }
    }

  private suspend fun imageReferences(): Set<UUID> =
    storage
      .fetchAll(ClipSortOrder.CREATED_AT)
      .mapNotNull { (it.content as? ClipContent.Image)?.image?.fileID }
      .toSet()

  private suspend fun clean(fileID: UUID): ClipImageCleanupState =
    try {
      val references = imageReferences()
      io { clean(fileID, fileID in references) }
      ClipImageCleanupState.Completed
    } catch (error: CancellationException) {
      throw error
    } catch (error: Exception) {
      ClipImageCleanupState.Pending(fileID)
    }

  private fun clean(
    fileID: UUID,
    referenced: Boolean,
  ) {
    if (referenced) files.finishPending(fileID) else files.delete(fileID)
  }

  private suspend fun <T> serialized(operation: suspend () -> T): T = mutex.withLock { operation() }

  private suspend fun <T> io(operation: () -> T): T =
    withContext(Dispatchers.IO) {
      ensureActive()
      operation()
    }

  private companion object {
    const val PREVIEW_PIXEL_DIMENSION = 1600
  }
}
