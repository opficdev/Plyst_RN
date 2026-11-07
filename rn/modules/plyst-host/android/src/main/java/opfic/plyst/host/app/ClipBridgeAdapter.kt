package opfic.plyst.host.app

import android.net.Uri
import java.io.File
import java.util.UUID
import kotlin.coroutines.cancellation.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch
import opfic.plyst.bridge.ClipBridgeChange
import opfic.plyst.bridge.ClipBridgeClipboardSaveResult
import opfic.plyst.bridge.ClipBridgeCopyResult
import opfic.plyst.bridge.ClipBridgeError
import opfic.plyst.bridge.ClipBridgeException
import opfic.plyst.bridge.ClipBridgePhotoSaveResult
import opfic.plyst.bridge.ClipBridgeProvider
import opfic.plyst.bridge.ClipBridgeRecord
import opfic.plyst.host.adapter.clip.ClipCoreAdapter
import opfic.plyst.host.adapter.clip.ClipStorageError
import opfic.plyst.host.adapter.clip.ClipStorageEvent
import opfic.plyst.host.adapter.clip.ClipboardCopyResult
import opfic.plyst.host.adapter.clip.ClipboardSaveResult
import opfic.plyst.host.model.Clip
import opfic.plyst.host.model.ClipContent
import opfic.plyst.host.model.ClipImageMetadata
import opfic.plyst.host.model.ClipSearchQuery
import opfic.plyst.host.model.ClipSortOrder
import opfic.plyst.host.model.ClipUpdate
import opfic.plyst.host.service.clip.clipboard.ClipboardService
import opfic.plyst.host.service.clip.photolibrary.ClipPhotoLibrarySaveResult
import opfic.plyst.host.service.clip.photolibrary.ClipPhotoLibraryService

// ClipCoreAdapter와 Service API만 호출하여 브릿지 값과 오류 코드로 바꿈
class ClipBridgeAdapter(
  private val core: ClipCoreAdapter,
  private val clipboard: ClipboardService,
  private val photos: ClipPhotoLibraryService,
  // 응답과 별개로 이어서 실행할 정리 작업의 수명
  private val scope: CoroutineScope,
) : ClipBridgeProvider {
  override fun changes(): Flow<ClipBridgeChange> =
    core.changes().map { event ->
      when (event) {
        is ClipStorageEvent.Inserted -> ClipBridgeChange(ClipBridgeChange.Kind.INSERTED, event.clip.id)
        is ClipStorageEvent.Updated -> ClipBridgeChange(ClipBridgeChange.Kind.UPDATED, event.clip.id)
        is ClipStorageEvent.Deleted -> ClipBridgeChange(ClipBridgeChange.Kind.DELETED, event.id)
      }
    }

  override suspend fun clip(id: UUID): ClipBridgeRecord? =
    bridged(ClipBridgeError.READ_FAILED) { core.fetch(id)?.let(::record) }

  override suspend fun clips(): List<ClipBridgeRecord> =
    bridged(ClipBridgeError.READ_FAILED) { core.fetchAll(ClipSortOrder.CREATED_AT).map(::record) }

  override suspend fun searchHistory(): List<String> =
    bridged(ClipBridgeError.READ_FAILED) { core.fetchSearchHistory().terms }

  override suspend fun recordSearchTerm(term: String): List<String>? =
    bridged(ClipBridgeError.WRITE_FAILED) {
      val query = ClipSearchQuery.of(term) ?: return@bridged null
      core.recordSearchTerm(query).terms
    }

  override suspend fun removeSearchTerm(term: String): List<String> =
    bridged(ClipBridgeError.WRITE_FAILED) { core.removeSearchTerm(term).terms }

  override suspend fun removeAllSearchTerms() {
    try {
      core.removeAllSearchTerms()
    } catch (error: CancellationException) {
      throw error
    } catch (error: Exception) {
      throw ClipBridgeException(ClipBridgeError.WRITE_FAILED)
    }
  }

  override suspend fun updateClip(
    id: UUID,
    name: String?,
    memo: String?,
    isPinned: Boolean,
  ): ClipBridgeRecord? =
    bridged(ClipBridgeError.WRITE_FAILED) {
      try {
        val change = ClipUpdate.Details(name, memo, isPinned, System.currentTimeMillis())
        record(core.update(id, change))
      } catch (error: ClipStorageError.NotFound) {
        null
      }
    }

  override suspend fun deleteClip(id: UUID) =
    bridged(ClipBridgeError.WRITE_FAILED) {
      try {
        core.delete(id)
      } catch (error: ClipStorageError.NotFound) {
        // 이미 없으면 삭제된 것으로 처리
      }
      Unit
    }

  override suspend fun saveCurrentClipboard(): ClipBridgeClipboardSaveResult =
    try {
      when (clipboard.saveCurrentClipboard()) {
        is ClipboardSaveResult.Saved -> ClipBridgeClipboardSaveResult.SAVED
        is ClipboardSaveResult.SavedWithPendingCleanup -> {
          scope.launch {
            try {
              core.recoverPendingCleanup()
            } catch (error: Exception) {
              // 다음 시작에서 다시 정리
            }
          }
          ClipBridgeClipboardSaveResult.SAVED
        }
        ClipboardSaveResult.Empty -> ClipBridgeClipboardSaveResult.EMPTY
        ClipboardSaveResult.Unsupported -> ClipBridgeClipboardSaveResult.UNSUPPORTED
        ClipboardSaveResult.AccessFailed -> ClipBridgeClipboardSaveResult.ACCESS_FAILED
        ClipboardSaveResult.InvalidImage -> ClipBridgeClipboardSaveResult.INVALID_IMAGE
      }
    } catch (error: CancellationException) {
      throw error
    } catch (error: Exception) {
      throw ClipBridgeException(ClipBridgeError.SAVE_FAILED)
    }

  override suspend fun copyClip(id: UUID): ClipBridgeCopyResult? =
    try {
      when (clipboard.copy(id)) {
        is ClipboardCopyResult.Copied -> ClipBridgeCopyResult.COPIED
        is ClipboardCopyResult.CopiedWithoutLastUsedAt -> ClipBridgeCopyResult.COPIED_WITHOUT_LAST_USED_AT
        is ClipboardCopyResult.WriteNotObserved -> ClipBridgeCopyResult.WRITE_NOT_OBSERVED
      }
    } catch (error: CancellationException) {
      throw error
    } catch (error: ClipStorageError.NotFound) {
      null
    } catch (error: Exception) {
      throw ClipBridgeException(ClipBridgeError.COPY_FAILED)
    }

  override suspend fun getClipImagePreview(id: UUID): String? =
    imageFile(id) { image -> core.makePreviewFile(image) }

  override suspend fun getClipThumbnail(
    id: UUID,
    maximumPixelDimension: Int,
  ): String? = imageFile(id) { image -> core.makeThumbnailFile(image, maximumPixelDimension) }

  override suspend fun saveClipImageToPhotos(id: UUID): ClipBridgePhotoSaveResult? =
    try {
      when (photos.save(id)) {
        ClipPhotoLibrarySaveResult.SAVED -> ClipBridgePhotoSaveResult.SAVED
        ClipPhotoLibrarySaveResult.DENIED -> ClipBridgePhotoSaveResult.DENIED
        ClipPhotoLibrarySaveResult.RESTRICTED -> ClipBridgePhotoSaveResult.RESTRICTED
      }
    } catch (error: CancellationException) {
      throw error
    } catch (error: ClipStorageError.NotFound) {
      null
    } catch (error: Exception) {
      throw ClipBridgeException(ClipBridgeError.PHOTO_SAVE_FAILED)
    }

  private suspend fun imageFile(
    id: UUID,
    make: suspend (ClipImageMetadata) -> File,
  ): String? =
    try {
      val image = (core.fetch(id)?.content as? ClipContent.Image)?.image
      image?.let { Uri.fromFile(make(it)).toString() }
    } catch (error: CancellationException) {
      throw error
    } catch (error: Exception) {
      throw ClipBridgeException(ClipBridgeError.IMAGE_UNAVAILABLE)
    }

  // 저장소 오류 중 CorruptedData만 따로 알리고 나머지는 연산별 코드로 바꿈
  private suspend fun <T> bridged(
    fallback: ClipBridgeError,
    operation: suspend () -> T,
  ): T =
    try {
      operation()
    } catch (error: CancellationException) {
      throw error
    } catch (error: ClipStorageError.CorruptedData) {
      throw ClipBridgeException(ClipBridgeError.CORRUPTED_DATA)
    } catch (error: Exception) {
      throw ClipBridgeException(fallback)
    }

  private fun record(clip: Clip): ClipBridgeRecord {
    val content = clip.content
    return ClipBridgeRecord(
      id = clip.id,
      text = (content as? ClipContent.Text)?.text,
      image =
        (content as? ClipContent.Image)?.image?.let {
          ClipBridgeRecord.Image(
            byteCount = it.byteCount,
            contentType = it.contentType,
            pixelWidth = it.pixelWidth,
            pixelHeight = it.pixelHeight,
          )
        },
      name = clip.name,
      memo = clip.memo,
      pinnedAt = clip.pinnedAt?.toDouble(),
      isWebLink = content.isWebLink,
      createdAt = clip.createdAt.toDouble(),
      lastUsedAt = clip.lastUsedAt?.toDouble(),
    )
  }
}
