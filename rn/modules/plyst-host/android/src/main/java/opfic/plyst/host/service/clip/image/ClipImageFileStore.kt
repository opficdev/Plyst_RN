package opfic.plyst.host.service.clip.image

import java.io.File
import java.io.IOException
import java.nio.ByteBuffer
import java.util.UUID
import opfic.plyst.core.ClipImageFiles
import opfic.plyst.core.ClipImageFilesException
import opfic.plyst.host.model.ClipImageMetadata

// 주입한 전용 루트에서 원본 바이트를 관리
// 파일 규칙은 코어의 ClipImageFiles가 소유하고 이 타입은 오류 변환, 원본 읽기를 담당
// 같은 루트의 변경은 ClipImageService 하나가 조율해야 함
class ClipImageFileStore(root: File) {
  private val files: ClipImageFiles
  private val bufferLock = Any()
  private val reusableBuffer by lazy { ByteBuffer.allocateDirect(REUSABLE_BUFFER_CAPACITY) }

  init {
    if (!root.isAbsolute || root.path.contains('\u0000')) throw ClipImageFileError.InvalidRoot
    files = converted(ClipImageFileError.WriteFailed) { ClipImageFiles.open(root.canonicalPath) }
  }

  // 검증한 원본을 재인코딩 없이 저장
  // 반환된 fileID의 정리 후보는 메타데이터 저장 확정 후 해제해야 함
  fun save(data: ByteArray): ClipImageMetadata {
    val properties = ClipImageCodec.properties(data)
    val fileID = converted(ClipImageFileError.WriteFailed) { UUID.fromString(withDirectBuffer(data) { files.save(it) }) }
    return ClipImageMetadata(
      fileID = fileID,
      contentType = properties.type,
      pixelWidth = properties.width,
      pixelHeight = properties.height,
      byteCount = data.size,
    )
  }

  fun load(fileID: UUID): ByteArray {
    val path = converted(ClipImageFileError.ReadFailed) { files.originalPath(wireID(fileID)) }
    return try {
      File(path).readBytes()
    } catch (error: IOException) {
      throw ClipImageFileError.ReadFailed
    }
  }

  // 저장된 메타데이터와 원본을 대조하며 파일이나 이미지 표현을 변경하지 않음
  fun load(image: ClipImageMetadata): ByteArray {
    val data = load(image.fileID)
    if (data.size != image.byteCount) throw ClipImageFileError.CorruptedImage(image.fileID)
    val properties =
      try {
        ClipImageCodec.properties(data)
      } catch (error: ClipImageFileError) {
        if (error == ClipImageFileError.InvalidImage || error == ClipImageFileError.UnsupportedImage) {
          throw ClipImageFileError.CorruptedImage(image.fileID)
        }
        throw error
      }
    if (properties.type != image.contentType ||
      properties.width != image.pixelWidth ||
      properties.height != image.pixelHeight
    ) {
      throw ClipImageFileError.CorruptedImage(image.fileID)
    }
    return data
  }

  // 원본을 메모리에 모두 올리지 않고 첫 프레임을 표시 크기로 축소한 PNG
  // 저장된 파일은 변경하지 않음
  fun loadThumbnail(
    image: ClipImageMetadata,
    maximumPixelDimension: Int,
  ): ByteArray {
    if (maximumPixelDimension <= 0) throw ClipImageFileError.ReadFailed
    val path =
      converted(ClipImageFileError.ReadFailed) {
        files.validatedOriginalPath(wireID(image.fileID), image.byteCount.toLong())
      }
    return ClipImageCodec.thumbnail(File(path), image, maximumPixelDimension)
  }

  // 원본에서 만든 축소본을 매번 원자적으로 덮어씀
  fun writePreview(
    image: ClipImageMetadata,
    maximumPixelDimension: Int,
  ): File {
    val data = loadThumbnail(image, maximumPixelDimension)
    return converted(ClipImageFileError.WriteFailed) {
      withDirectBuffer(data) { File(files.writePreview(wireID(image.fileID), it)) }
    }
  }

  // 요청한 크기의 축소본을 매번 원자적으로 덮어씀
  fun writeThumbnail(
    image: ClipImageMetadata,
    maximumPixelDimension: Int,
  ): File {
    val data = loadThumbnail(image, maximumPixelDimension)
    return converted(ClipImageFileError.WriteFailed) {
      withDirectBuffer(data) { File(files.writeThumbnail(wireID(image.fileID), maximumPixelDimension.toLong(), it)) }
    }
  }

  // 이미 존재하지 않는 파일은 삭제된 것으로 처리
  fun delete(fileID: UUID) = converted(ClipImageFileError.DeleteFailed) { files.delete(wireID(fileID)) }

  fun markPending(fileID: UUID) = converted(ClipImageFileError.WriteFailed) { files.markPending(wireID(fileID)) }

  fun finishPending(fileID: UUID) = converted(ClipImageFileError.DeleteFailed) { files.finishPending(wireID(fileID)) }

  // 정상 원본을 일괄 삭제하지 않음
  // 정리 후보와 저장 중단으로 불완전한 디렉터리만 반환
  fun pendingFileIDs(): List<UUID> = converted(ClipImageFileError.ReadFailed) { files.pendingFileIds() }.map(UUID::fromString)

  private fun wireID(fileID: UUID) = fileID.toString().uppercase()

  // UniFFI 바이트 인자는 direct buffer만 받음
  // 상한 이하 데이터는 버퍼를 재사용해 할당 비용을 줄이고 초과분은 메모리에 남지 않게 따로 할당
  private inline fun <T> withDirectBuffer(
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

  private companion object {
    // 일반적인 사진 원본과 썸네일이 들어가는 크기
    const val REUSABLE_BUFFER_CAPACITY = 4 * 1024 * 1024
  }
}

// 코어 오류를 저장소 오류로 변환
// 패닉은 연산별 대체 오류로 전달
private inline fun <T> converted(
  fallback: ClipImageFileError,
  body: () -> T,
): T =
  try {
    body()
  } catch (error: ClipImageFilesException) {
    throw fileError(error)
  } catch (error: Exception) {
    throw fallback
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
