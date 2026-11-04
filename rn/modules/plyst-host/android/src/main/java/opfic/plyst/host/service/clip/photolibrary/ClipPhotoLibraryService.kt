package opfic.plyst.host.service.clip.photolibrary

import java.util.UUID
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import opfic.plyst.host.model.ClipContent
import opfic.plyst.host.service.clip.image.ClipImageFileError
import opfic.plyst.host.service.clip.image.ClipImageService
import opfic.plyst.host.service.clip.storage.ClipStorageError
import opfic.plyst.host.service.clip.storage.ClipStorageService

enum class ClipPhotoLibrarySaveResult {
  SAVED,
  DENIED,
  RESTRICTED,
}

// 명시적인 사용자 요청에서만 사진 모음에 원본을 추가
// storage와 images는 같은 저장소를 사용
class ClipPhotoLibraryService(
  private val storage: ClipStorageService,
  private val images: ClipImageService,
  private val writer: PhotoLibraryWriter,
) {
  // 권한 대기 중에는 이미지 서비스의 작업 순서를 점유하지 않음
  suspend fun save(id: UUID): ClipPhotoLibrarySaveResult {
    when (writer.requestAddAuthorization()) {
      PhotoLibraryAuthorization.DENIED -> return ClipPhotoLibrarySaveResult.DENIED
      PhotoLibraryAuthorization.RESTRICTED -> return ClipPhotoLibrarySaveResult.RESTRICTED
      PhotoLibraryAuthorization.AUTHORIZED -> Unit
    }
    currentCoroutineContext().ensureActive()
    val clip = storage.fetch(id) ?: throw ClipStorageError.NotFound(id)
    val image = (clip.content as? ClipContent.Image)?.image ?: throw ClipImageFileError.NotImage(id)
    val data = images.loadImage(image)
    currentCoroutineContext().ensureActive()
    writer.write(data, image.contentType)
    // 쓰기 확정 이후에는 취소를 다시 확인하지 않음
    return ClipPhotoLibrarySaveResult.SAVED
  }
}
