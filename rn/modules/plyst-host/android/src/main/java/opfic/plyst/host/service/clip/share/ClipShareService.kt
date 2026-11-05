package opfic.plyst.host.service.clip.share

import android.content.ContentResolver
import android.content.Context
import android.net.Uri
import android.webkit.MimeTypeMap
import java.io.ByteArrayOutputStream
import java.io.IOException
import java.net.URI
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.withContext
import opfic.plyst.host.model.Clip
import opfic.plyst.host.model.ClipContent
import opfic.plyst.host.service.clip.download.ClipImageDownloadError
import opfic.plyst.host.service.clip.download.ClipImageDownloadService
import opfic.plyst.host.service.clip.image.ClipImageFileError
import opfic.plyst.host.service.clip.image.ClipImageService
import opfic.plyst.host.service.clip.storage.ClipStorageService

// 공유 시트로 받은 항목을 클립으로 저장
// 여러 항목은 다루지 않음
//
// 이미지 첨부는 변환 없이 원본 바이트를 이름 없는 이미지 클립으로 저장
// 그 외에는 텍스트나 URL을 텍스트 클립으로 저장
// 텍스트 전체가 URL 하나이고 경로나 쿼리 값에 든 주소의 확장자가 이미지 형식이면 이미지를 내려받아 원본 URL을 메모로 둔 이미지 클립으로 저장
// Android는 URL과 텍스트를 형식으로 구분하지 않으므로 URL 여부는 값으로 판단
// 내려받기나 이미지 검증에 실패하면 같은 URL을 텍스트 클립으로 저장하며 일반 페이지 링크는 네트워크 요청을 하지 않음
// 저장을 시도할 때마다 첨부를 다시 읽으므로 읽기 실패 후에도 같은 항목으로 다시 시도할 수 있음
// 읽기에 실패하면 저장소에 쓰지 않음
// 이미지 검증 오류와 저장소 오류와 CancellationException은 그대로 전파
class ClipShareService(
  private val context: Context,
  private val storage: ClipStorageService,
  private val images: ClipImageService,
  private val downloads: ClipImageDownloadService,
) {
  // 공유 화면은 앱과 같은 프로세스이므로 큰 이미지의 메모리 부족이 앱 전체를 끝내지 않게 읽기 실패로 바꿈
  suspend fun save(item: ClipShareItem): ClipShareSaveResult =
    try {
      saveItem(item)
    } catch (error: OutOfMemoryError) {
      ClipShareSaveResult.LoadFailed
    }

  private suspend fun saveItem(item: ClipShareItem): ClipShareSaveResult {
    val data =
      try {
        loadImageData(item)
      } catch (error: IOException) {
        return ClipShareSaveResult.LoadFailed
      } catch (error: SecurityException) {
        return ClipShareSaveResult.LoadFailed
      }
    if (data == null) return saveText(item)
    // 저장이 시작된 뒤에는 취소를 다시 확인하지 않음
    currentCoroutineContext().ensureActive()
    return withContext(NonCancellable) { ClipShareSaveResult.Saved(images.saveImage(data).value) }
  }

  private suspend fun saveText(item: ClipShareItem): ClipShareSaveResult {
    val text = item.text
    if (text == null || !ClipContent.Text(text).isValid) return ClipShareSaveResult.Empty
    if (isImageURL(text)) saveDownloadedImage(text)?.let { return it }
    // 저장이 시작된 뒤에는 취소를 다시 확인하지 않음
    currentCoroutineContext().ensureActive()
    val clip = Clip(content = ClipContent.Text(text), name = item.title)
    withContext(NonCancellable) { storage.insert(clip) }
    return ClipShareSaveResult.Saved(clip)
  }

  // 내려받기나 이미지 검증에 실패하면 null이며 텍스트 경로가 이어서 처리
  // 저장소 오류와 취소는 전파
  private suspend fun saveDownloadedImage(url: String): ClipShareSaveResult? {
    val data =
      try {
        downloads.loadImage(url)
      } catch (error: ClipImageDownloadError) {
        return null
      }
    // 저장이 시작된 뒤에는 취소를 다시 확인하지 않음
    currentCoroutineContext().ensureActive()
    return try {
      withContext(NonCancellable) { ClipShareSaveResult.Saved(images.saveImage(data, memo = url).value) }
    } catch (error: ClipImageFileError) {
      if (error != ClipImageFileError.InvalidImage && error != ClipImageFileError.UnsupportedImage) throw error
      null
    }
  }

  // 단일 http 또는 https URL이고 경로나 쿼리 값에 든 주소의 확장자가 이미지 형식일 때만 true
  // 네트워크 요청은 하지 않음
  private fun isImageURL(text: String): Boolean {
    if (!ClipContent.Text(text).isWebLink || runCatching { URI(text) }.isFailure) return false
    val uri = Uri.parse(text)
    val queryValues = uri.queryParameterNames.flatMap { uri.getQueryParameters(it) }
    return (listOf(text) + queryValues).any(::hasImageExtension)
  }

  private fun hasImageExtension(url: String): Boolean {
    val pathExtension = Uri.parse(url).path?.substringAfterLast('/')?.substringAfterLast('.', "") ?: return false
    return MimeTypeMap.getSingleton().getMimeTypeFromExtension(pathExtension.lowercase())?.startsWith("image/") == true
  }

  // 이미지 첨부가 없으면 null이며 텍스트 경로가 이어서 처리
  // 공유 대상은 앱의 권한으로 URI를 읽으므로 앱 내부 파일을 가리킬 수 있는 file URI는 읽지 않음
  private suspend fun loadImageData(item: ClipShareItem): ByteArray? {
    val stream = item.stream ?: return null
    return withContext(Dispatchers.IO) {
      val resolver = context.contentResolver
      if (item.type?.startsWith("image/") != true && resolver.getType(stream)?.startsWith("image/") != true) return@withContext null
      if (stream.scheme != ContentResolver.SCHEME_CONTENT) throw IOException()
      resolver.openInputStream(stream)?.use { input ->
        val output = ByteArrayOutputStream()
        val buffer = ByteArray(BUFFER_BYTE_COUNT)
        while (true) {
          // 취소하면 느린 읽기를 끝까지 기다리지 않음
          ensureActive()
          val count = input.read(buffer)
          if (count < 0) break
          output.write(buffer, 0, count)
        }
        output.toByteArray()
      } ?: throw IOException()
    }
  }

  private companion object {
    const val BUFFER_BYTE_COUNT = 64 * 1024
  }
}
