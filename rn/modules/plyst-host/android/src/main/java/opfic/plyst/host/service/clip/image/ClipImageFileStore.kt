package opfic.plyst.host.service.clip.image

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.media.ExifInterface
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.IOException
import java.util.UUID
import kotlin.math.max
import kotlin.math.roundToInt
import opfic.plyst.host.model.ClipImageMetadata

// 주입한 전용 루트에서 원본 바이트를 관리
// 같은 루트의 변경은 ClipImageService 하나가 조율해야 함
// <fileID>/preview와 <fileID>/thumbnail-<px>는 원본에서 다시 만들 수 있는 파생 파일
class ClipImageFileStore(root: File) {
  private val root: File

  init {
    if (!root.isAbsolute || root.path.contains('\u0000')) throw ClipImageFileError.InvalidRoot
    if (!(root.isDirectory || root.mkdirs())) throw ClipImageFileError.WriteFailed
    this.root = root.canonicalFile
    validateRoot()
  }

  // 검증한 원본을 재인코딩 없이 저장
  // 반환된 fileID의 정리 후보는 메타데이터 저장 확정 후 해제해야 함
  fun save(data: ByteArray): ClipImageMetadata {
    val properties = imageProperties(data)
    validateRoot()
    var fileID = UUID.randomUUID()
    while (directoryFile(fileID).exists()) fileID = UUID.randomUUID()
    val directory = directoryFile(fileID)
    try {
      if (!directory.mkdir()) throw IOException()
      markPending(fileID)
      writeAtomically(File(directory, ORIGINAL), data)
    } catch (error: Exception) {
      // 실패한 정리는 후보 또는 불완전한 디렉터리로 남음
      runCatching { delete(fileID) }
      throw ClipImageFileError.WriteFailed
    }
    return ClipImageMetadata(
      fileID = fileID,
      contentType = properties.type,
      pixelWidth = properties.width,
      pixelHeight = properties.height,
      byteCount = data.size,
    )
  }

  fun load(fileID: UUID): ByteArray {
    val directory = directory(fileID) ?: throw ClipImageFileError.NotFound(fileID)
    val original = File(directory, ORIGINAL)
    if (!original.exists()) throw ClipImageFileError.NotFound(fileID)
    if (!isRegularFile(original)) throw ClipImageFileError.UnsafePath
    return try {
      original.readBytes()
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
        imageProperties(data)
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
    val original = validatedOriginal(image)
    val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
    BitmapFactory.decodeFile(original.path, bounds)
    if (bounds.outMimeType?.let(ClipImageContentType::identifier) != image.contentType ||
      bounds.outWidth != image.pixelWidth ||
      bounds.outHeight != image.pixelHeight
    ) {
      throw ClipImageFileError.CorruptedImage(image.fileID)
    }
    val options = BitmapFactory.Options().apply { inSampleSize = sampleSize(bounds.outWidth, bounds.outHeight, maximumPixelDimension) }
    val decoded = BitmapFactory.decodeFile(original.path, options) ?: throw ClipImageFileError.CorruptedImage(image.fileID)
    val thumbnail = oriented(scaled(decoded, maximumPixelDimension), original)
    return ByteArrayOutputStream().use { output ->
      if (!thumbnail.compress(Bitmap.CompressFormat.PNG, 100, output)) throw ClipImageFileError.ReadFailed
      thumbnail.recycle()
      output.toByteArray()
    }
  }

  // 원본에서 만든 축소본을 매번 원자적으로 덮어씀
  fun writePreview(
    image: ClipImageMetadata,
    maximumPixelDimension: Int,
  ) = writeDerivedFile(PREVIEW, image, maximumPixelDimension)

  // 요청한 크기의 축소본을 매번 원자적으로 덮어씀
  fun writeThumbnail(
    image: ClipImageMetadata,
    maximumPixelDimension: Int,
  ) = writeDerivedFile("thumbnail-$maximumPixelDimension", image, maximumPixelDimension)

  // 이미 존재하지 않는 파일은 삭제된 것으로 처리
  fun delete(fileID: UUID) {
    val directory = directory(fileID) ?: return
    try {
      val original = File(directory, ORIGINAL)
      if (original.exists() && !original.delete()) throw IOException()
      directory.listFiles()?.filter { it.name != PENDING }?.forEach { if (!it.deleteRecursively()) throw IOException() }
      // 원본과 임시 파일이 모두 제거된 후에만 정리 기록을 해제
      finishPending(fileID)
      // 여기서 중단되면 원본이 없는 디렉터리를 복구 후보로 찾을 수 있음
      if (!directory.delete()) throw IOException()
    } catch (error: Exception) {
      throw ClipImageFileError.DeleteFailed
    }
  }

  fun markPending(fileID: UUID) {
    val directory = directory(fileID) ?: return
    val marker = File(directory, PENDING)
    validateFile(marker)
    try {
      writeAtomically(marker, ByteArray(0))
    } catch (error: IOException) {
      throw ClipImageFileError.WriteFailed
    }
  }

  fun finishPending(fileID: UUID) {
    val directory = directory(fileID) ?: return
    val marker = File(directory, PENDING)
    if (!marker.exists()) return
    validateFile(marker)
    if (!marker.delete()) throw ClipImageFileError.DeleteFailed
  }

  // 정상 원본을 일괄 삭제하지 않음
  // 정리 후보와 저장 중단으로 불완전한 디렉터리만 반환
  fun pendingFileIDs(): List<UUID> {
    validateRoot()
    val entries = root.listFiles() ?: throw ClipImageFileError.ReadFailed
    return entries
      .mapNotNull { entry ->
        val fileID = runCatching { UUID.fromString(entry.name) }.getOrNull() ?: return@mapNotNull null
        if (fileID.toString().uppercase() != entry.name) return@mapNotNull null
        val directory = directory(fileID) ?: return@mapNotNull null
        val marker = File(directory, PENDING)
        validateFile(marker)
        fileID.takeIf { marker.exists() || !File(directory, ORIGINAL).exists() }
      }.sortedBy { it.toString().uppercase() }
  }

  private fun writeDerivedFile(
    name: String,
    image: ClipImageMetadata,
    maximumPixelDimension: Int,
  ): File {
    val data = loadThumbnail(image, maximumPixelDimension)
    val directory = directory(image.fileID) ?: throw ClipImageFileError.NotFound(image.fileID)
    val file = File(directory, name)
    validateFile(file)
    try {
      writeAtomically(file, data)
    } catch (error: IOException) {
      throw ClipImageFileError.WriteFailed
    }
    return file
  }

  private fun validatedOriginal(image: ClipImageMetadata): File {
    val directory = directory(image.fileID) ?: throw ClipImageFileError.NotFound(image.fileID)
    val original = File(directory, ORIGINAL)
    if (!original.exists()) throw ClipImageFileError.NotFound(image.fileID)
    if (!isRegularFile(original)) throw ClipImageFileError.UnsafePath
    if (original.length() != image.byteCount.toLong()) throw ClipImageFileError.CorruptedImage(image.fileID)
    return original
  }

  private fun imageProperties(data: ByteArray): ImageProperties {
    if (data.isEmpty()) throw ClipImageFileError.InvalidImage
    val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
    BitmapFactory.decodeByteArray(data, 0, data.size, bounds)
    val mimeType = bounds.outMimeType ?: throw ClipImageFileError.InvalidImage
    val type = ClipImageContentType.identifier(mimeType) ?: throw ClipImageFileError.UnsupportedImage
    // 잘린 GIF도 남은 프레임으로 디코딩되므로 종료 바이트(0x3B)로 잘림을 판별
    if (type == "com.compuserve.gif" && data.last() != 0x3B.toByte()) throw ClipImageFileError.InvalidImage
    if (bounds.outWidth <= 0 || bounds.outHeight <= 0) throw ClipImageFileError.InvalidImage
    // 원본 해상도 비트맵을 만들지 않도록 크기는 헤더로 읽고 무결성은 축소 디코딩으로 확인
    val validation =
      BitmapFactory.Options().apply {
        inSampleSize = sampleSize(bounds.outWidth, bounds.outHeight, VALIDATION_PIXEL_DIMENSION)
      }
    val bitmap = BitmapFactory.decodeByteArray(data, 0, data.size, validation) ?: throw ClipImageFileError.InvalidImage
    bitmap.recycle()
    return ImageProperties(type, bounds.outWidth, bounds.outHeight)
  }

  // 긴 변이 요청 크기보다 작아지지 않는 가장 큰 2의 거듭제곱
  private fun sampleSize(
    width: Int,
    height: Int,
    maximumPixelDimension: Int,
  ): Int {
    var size = 1
    while (maximumPixelDimension <= max(width, height) / (size * 2)) size *= 2
    return size
  }

  // 긴 변을 요청 크기에 맞추며 원본보다 키우지 않음
  private fun scaled(
    bitmap: Bitmap,
    maximumPixelDimension: Int,
  ): Bitmap {
    val longest = max(bitmap.width, bitmap.height)
    if (longest <= maximumPixelDimension) return bitmap
    val scale = maximumPixelDimension.toFloat() / longest
    val width = max(1, (bitmap.width * scale).roundToInt())
    val height = max(1, (bitmap.height * scale).roundToInt())
    return Bitmap.createScaledBitmap(bitmap, width, height, true).also { if (it !== bitmap) bitmap.recycle() }
  }

  // iOS 썸네일처럼 EXIF 방향을 적용
  private fun oriented(
    bitmap: Bitmap,
    original: File,
  ): Bitmap {
    val orientation =
      runCatching {
        ExifInterface(original.path).getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL)
      }.getOrDefault(ExifInterface.ORIENTATION_NORMAL)
    val matrix = Matrix()
    when (orientation) {
      ExifInterface.ORIENTATION_FLIP_HORIZONTAL -> matrix.setScale(-1f, 1f)
      ExifInterface.ORIENTATION_ROTATE_180 -> matrix.setRotate(180f)
      ExifInterface.ORIENTATION_FLIP_VERTICAL -> matrix.setScale(1f, -1f)
      ExifInterface.ORIENTATION_TRANSPOSE -> matrix.apply { setRotate(90f) }.postScale(-1f, 1f)
      ExifInterface.ORIENTATION_ROTATE_90 -> matrix.setRotate(90f)
      ExifInterface.ORIENTATION_TRANSVERSE -> matrix.apply { setRotate(-90f) }.postScale(-1f, 1f)
      ExifInterface.ORIENTATION_ROTATE_270 -> matrix.setRotate(-90f)
      else -> return bitmap
    }
    return Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, matrix, true).also {
      if (it !== bitmap) bitmap.recycle()
    }
  }

  private fun writeAtomically(
    file: File,
    data: ByteArray,
  ) {
    val temporary = File(file.parentFile, ".${file.name}.${UUID.randomUUID()}")
    try {
      temporary.writeBytes(data)
      if (!temporary.renameTo(file)) throw IOException()
    } finally {
      temporary.delete()
    }
  }

  private fun directoryFile(fileID: UUID) = File(root, fileID.toString().uppercase())

  private fun directory(fileID: UUID): File? {
    validateRoot()
    val directory = directoryFile(fileID)
    if (!directory.exists()) return null
    if (!directory.isDirectory || directory.canonicalFile != directory.absoluteFile) throw ClipImageFileError.UnsafePath
    return directory
  }

  private fun validateRoot() {
    if (!root.isDirectory || root.canonicalFile != root) throw ClipImageFileError.UnsafePath
  }

  private fun validateFile(file: File) {
    if (file.exists() && !isRegularFile(file)) throw ClipImageFileError.UnsafePath
  }

  private fun isRegularFile(file: File) = file.isFile && file.canonicalFile == file.absoluteFile

  private data class ImageProperties(
    val type: String,
    val width: Int,
    val height: Int,
  )

  private companion object {
    // 저장 전 검증에서 축소 디코딩하는 긴 변의 최대 픽셀 수
    const val VALIDATION_PIXEL_DIMENSION = 64
    const val ORIGINAL = "original"
    const val PENDING = "pending"
    const val PREVIEW = "preview"
  }
}
