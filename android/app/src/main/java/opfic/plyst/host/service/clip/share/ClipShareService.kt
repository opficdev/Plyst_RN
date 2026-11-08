package opfic.plyst.host.service.clip.share

import android.content.ContentResolver
import android.content.Context
import java.io.ByteArrayOutputStream
import java.io.IOException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.withContext
import opfic.plyst.host.adapter.clip.ClipCoreAdapter
import opfic.plyst.host.service.clip.download.SystemClipImageDownloader

// 공유 시트로 받은 항목을 클립으로 저장
// 여러 항목은 다루지 않음
//
// 이미지 첨부는 변환 없이 원본 바이트를 이름 없는 이미지 클립으로 저장
// 그 외에는 텍스트나 URL을 코어에 넘겨 저장
// Android는 URL과 텍스트를 형식으로 구분하지 않으므로 코어가 항상 내려받기를 판단
// 이미지 주소 판정, 내려받기 순서, 실패 시 텍스트 저장, 제목 정리는 코어가 결정
// 저장을 시도할 때마다 첨부를 다시 읽으므로 읽기 실패 후에도 같은 항목으로 다시 시도할 수 있음
// 읽기에 실패하면 저장소에 쓰지 않음
// 이미지 검증 오류와 저장소 오류와 CancellationException은 그대로 전파
class ClipShareService(
  private val context: Context,
  private val core: ClipCoreAdapter,
  private val downloader: SystemClipImageDownloader,
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
    return ClipShareSaveResult.Saved(core.saveImage(data).value)
  }

  private suspend fun saveText(item: ClipShareItem): ClipShareSaveResult {
    val text = item.text ?: return ClipShareSaveResult.Empty
    val clip = core.saveSharedText(text, item.title, downloader) ?: return ClipShareSaveResult.Empty
    return ClipShareSaveResult.Saved(clip)
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
