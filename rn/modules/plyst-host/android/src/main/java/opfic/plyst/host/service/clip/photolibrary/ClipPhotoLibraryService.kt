package opfic.plyst.host.service.clip.photolibrary

import java.util.UUID
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import opfic.plyst.host.model.ClipContent
import opfic.plyst.host.adapter.clip.ClipCoreAdapter
import opfic.plyst.host.adapter.clip.ClipImageFileError
import opfic.plyst.host.adapter.clip.ClipStorageError

enum class ClipPhotoLibrarySaveResult {
  SAVED,
  DENIED,
  RESTRICTED,
}

// 명시적인 사용자 요청에서만 사진 모음에 원본을 추가
class ClipPhotoLibraryService(
  private val core: ClipCoreAdapter,
  private val writer: PhotoLibraryWriter,
) {
  // 권한 대기 중에는 이미지 줄을 점유하지 않음
  suspend fun save(id: UUID): ClipPhotoLibrarySaveResult {
    when (writer.requestAddAuthorization()) {
      PhotoLibraryAuthorization.DENIED -> return ClipPhotoLibrarySaveResult.DENIED
      PhotoLibraryAuthorization.RESTRICTED -> return ClipPhotoLibrarySaveResult.RESTRICTED
      PhotoLibraryAuthorization.AUTHORIZED -> Unit
    }
    currentCoroutineContext().ensureActive()
    val clip = core.fetch(id) ?: throw ClipStorageError.NotFound(id)
    val image = (clip.content as? ClipContent.Image)?.image ?: throw ClipImageFileError.NotImage(id)
    val data = core.loadImage(image)
    currentCoroutineContext().ensureActive()
    writer.write(data, image.contentType)
    // 쓰기 확정 이후에는 취소를 다시 확인하지 않음
    return ClipPhotoLibrarySaveResult.SAVED
  }
}
