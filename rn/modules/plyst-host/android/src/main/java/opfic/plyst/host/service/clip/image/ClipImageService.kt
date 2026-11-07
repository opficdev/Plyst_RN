package opfic.plyst.host.service.clip.image

import java.io.File
import java.nio.ByteBuffer
import java.util.UUID
import kotlinx.coroutines.Dispatchers
import opfic.plyst.core.ClipCleanupValue
import opfic.plyst.core.ClipImageDraftValue
import opfic.plyst.core.ClipImageOperations
import opfic.plyst.host.model.Clip
import opfic.plyst.host.model.ClipImageMetadata
import opfic.plyst.host.model.clip
import opfic.plyst.host.model.coreValue
import opfic.plyst.host.model.referenceSeconds
import opfic.plyst.host.model.wellFormed
import opfic.plyst.host.service.clip.coreCall
import opfic.plyst.host.service.clip.serviceErrors
import opfic.plyst.host.service.clip.storage.ClipStorageError
import opfic.plyst.host.service.clip.storage.SQLiteClipStorageService

// 같은 루트의 이미지 쓰기와 복구는 코어의 ClipImageOperations가 조율
// 이 타입은 실행 위치, 값 변환, 오류 변환, 원본 읽기를 담당
// 미리보기와 썸네일은 원본에서 다시 만들 수 있는 파생 파일
class ClipImageService(
  storage: SQLiteClipStorageService,
  root: File,
) {
  // 코어 잠금 대기가 스레드를 하나만 점유하도록 한 줄로 실행
  private val dispatcher = Dispatchers.IO.limitedParallelism(1)
  private val bufferLock = Any()
  private val reusableBuffer by lazy { ByteBuffer.allocateDirect(REUSABLE_BUFFER_CAPACITY) }
  internal val core: ClipImageOperations

  init {
    if (!root.isAbsolute || root.path.contains('\u0000')) throw ClipImageFileError.InvalidRoot
    core =
      serviceErrors(ClipImageFileError.WriteFailed) {
        ClipImageOperations.open(storage.store, root.canonicalPath, ClipImageCodec)
      }
  }

  suspend fun saveImage(
    data: ByteArray,
    memo: String? = null,
    id: UUID = UUID.randomUUID(),
    createdAt: Long = System.currentTimeMillis(),
  ): ClipImageMutationResult<Clip> {
    val draft = ClipImageDraftValue(wireID(id), null, memo?.wellFormed, null, createdAt.referenceSeconds)
    val saved =
      coreCall(dispatcher, ClipImageFileError.WriteFailed) { cancellation ->
        val properties = ClipImageCodec.validated(data)
        withDirectBuffer(data) { core.saveImage(it, properties, draft, cancellation) }
      }
    return ClipImageMutationResult(saved.clip.clip ?: throw ClipStorageError.CorruptedData, cleanupState(saved.cleanup))
  }

  // 클립을 재조회하지 않고 전달받은 메타데이터에 대응하는 원본을 검증
  // 같은 실행 줄에서 읽으므로 삭제와 섞이지 않음
  suspend fun loadImage(image: ClipImageMetadata): ByteArray =
    coreCall(dispatcher, ClipImageFileError.ReadFailed) { File(core.loadImage(image.coreValue, it)).readBytes() }

  // 삭제와 직렬화하여 원본에서 미리보기 파일을 매번 다시 만듦
  suspend fun makePreviewFile(image: ClipImageMetadata): File =
    coreCall(dispatcher, ClipImageFileError.WriteFailed) { File(core.makePreview(image.coreValue, it)) }

  // 삭제와 직렬화하여 요청한 크기의 썸네일 파일을 매번 다시 만듦
  suspend fun makeThumbnailFile(
    image: ClipImageMetadata,
    maximumPixelDimension: Int,
  ): File =
    coreCall(dispatcher, ClipImageFileError.WriteFailed) {
      File(core.makeThumbnail(image.coreValue, maximumPixelDimension.toLong(), it))
    }

  // DB 삭제 확정 후 파일 정리에 실패해도 확정된 삭제를 실패로 반환하지 않음
  suspend fun delete(id: UUID): ClipImageMutationResult<UUID> {
    val cleanup = coreCall(dispatcher, ClipStorageError.WriteFailed) { core.deleteClip(wireID(id), it) }
    return ClipImageMutationResult(id, cleanupState(cleanup))
  }

  // 구성 이후 명시적으로 호출
  // 이번에 정리하지 못한 fileID만 반환
  // DB 조회에 실패하면 후보를 변경하지 않고 오류를 던짐
  suspend fun recoverPendingCleanup(): List<UUID> =
    coreCall(dispatcher, ClipImageFileError.DeleteFailed) { core.recoverPendingCleanup(it) }.map(UUID::fromString)

  // UniFFI 바이트 인자는 direct buffer만 받음
  // 상한 이하 데이터는 버퍼를 재사용해 할당 비용을 줄이고 초과분은 메모리에 남지 않게 따로 할당
  internal fun <T> withDirectBuffer(
    data: ByteArray,
    body: (ByteBuffer) -> T,
  ): T =
    synchronized(bufferLock) {
      val buffer = if (data.size <= REUSABLE_BUFFER_CAPACITY) reusableBuffer else ByteBuffer.allocateDirect(data.size)
      buffer.clear()
      buffer.put(data)
      buffer.flip()
      // 생성 코드는 포인터만 넘기므로 코어 호출이 끝날 때까지 버퍼 회수를 막음
      synchronized(buffer) { body(buffer) }
    }

  private fun wireID(id: UUID) = id.toString().uppercase()

  private fun cleanupState(value: ClipCleanupValue) =
    when (value) {
      is ClipCleanupValue.Completed -> ClipImageCleanupState.Completed
      is ClipCleanupValue.Pending -> ClipImageCleanupState.Pending(UUID.fromString(value.fileId))
    }

  private companion object {
    // 일반적인 사진 원본이 들어가는 크기
    const val REUSABLE_BUFFER_CAPACITY = 4 * 1024 * 1024
  }
}
