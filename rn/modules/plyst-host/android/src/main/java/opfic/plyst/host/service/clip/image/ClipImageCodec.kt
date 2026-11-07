package opfic.plyst.host.service.clip.image

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.media.ExifInterface
import java.io.ByteArrayOutputStream
import java.io.File
import kotlin.math.max
import kotlin.math.roundToInt
import opfic.plyst.core.ClipCodecException
import opfic.plyst.core.ClipImageCoding
import opfic.plyst.core.ClipImagePropertiesValue
import opfic.plyst.core.ClipImageValue

// 이미지 형식과 크기 판독, 저장 전 검증, 축소본 생성
// 파일 경로 규칙과 파일 쓰기는 소유하지 않음
// 코어가 부르는 구현은 모든 오류를 선언된 코덱 오류로 변환
object ClipImageCodec : ClipImageCoding {
  // 저장 전 검증에서 축소 디코딩하는 긴 변의 최대 픽셀 수
  private const val VALIDATION_PIXEL_DIMENSION = 64

  data class ImageProperties(
    val type: String,
    val width: Int,
    val height: Int,
  )

  override fun properties(path: String): ClipImagePropertiesValue = coded { validated(File(path).readBytes()) }

  override fun thumbnail(
    path: String,
    image: ClipImageValue,
    maximumPixelDimension: Long,
  ): ByteArray = coded { reduced(File(path), image, maximumPixelDimension.toInt()) }

  // 저장 전 검증
  // 검증을 통과한 이미지의 형식과 크기를 코어 값으로 반환
  fun validated(data: ByteArray): ClipImagePropertiesValue {
    val properties = properties(data)
    return ClipImagePropertiesValue(properties.type, properties.width.toLong(), properties.height.toLong())
  }

  private inline fun <T> coded(operation: () -> T): T =
    try {
      operation()
    } catch (error: ClipCodecException) {
      throw error
    } catch (error: ClipImageFileError.InvalidImage) {
      throw ClipCodecException.Corrupted()
    } catch (error: ClipImageFileError.UnsupportedImage) {
      throw ClipCodecException.Corrupted()
    } catch (error: ClipImageFileError.ReadFailed) {
      throw ClipCodecException.ReadFailed()
    } catch (error: java.io.IOException) {
      throw ClipCodecException.ReadFailed()
    } catch (error: Exception) {
      throw ClipCodecException.Unexpected()
    } catch (error: OutOfMemoryError) {
      throw ClipCodecException.Unexpected()
    }

  private fun properties(data: ByteArray): ImageProperties {
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

  // 원본을 메모리에 모두 올리지 않고 첫 프레임을 표시 크기로 축소한 PNG
  // 저장된 파일은 변경하지 않음
  private fun reduced(
    original: File,
    image: ClipImageValue,
    maximumPixelDimension: Int,
  ): ByteArray {
    val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
    BitmapFactory.decodeFile(original.path, bounds)
    if (bounds.outMimeType?.let(ClipImageContentType::identifier) != image.contentType ||
      bounds.outWidth.toLong() != image.pixelWidth ||
      bounds.outHeight.toLong() != image.pixelHeight
    ) {
      throw ClipCodecException.Corrupted()
    }
    val options = BitmapFactory.Options().apply { inSampleSize = sampleSize(bounds.outWidth, bounds.outHeight, maximumPixelDimension) }
    val decoded = BitmapFactory.decodeFile(original.path, options) ?: throw ClipCodecException.Corrupted()
    val thumbnail = oriented(scaled(decoded, maximumPixelDimension), original)
    return ByteArrayOutputStream().use { output ->
      if (!thumbnail.compress(Bitmap.CompressFormat.PNG, 100, output)) throw ClipImageFileError.ReadFailed
      thumbnail.recycle()
      output.toByteArray()
    }
  }
}
