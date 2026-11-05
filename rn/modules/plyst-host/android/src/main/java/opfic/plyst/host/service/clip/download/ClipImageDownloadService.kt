package opfic.plyst.host.service.clip.download

import java.io.ByteArrayOutputStream
import java.io.IOException
import java.net.HttpURLConnection
import java.net.MalformedURLException
import java.net.URL
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runInterruptible
import kotlinx.coroutines.withTimeoutOrNull

// 이미지 URL의 응답 본문을 최대 바이트 수 안에서 메모리로 내려받음
// 요청은 GET 하나이며 쿠키와 캐시를 쓰지 않음
// 응답이 2xx이고 Content-Type이 이미지일 때만 본문을 읽으며 검증과 저장은 하지 않음
// 작업을 취소하면 전송을 중단하고 CancellationException을 전파
class ClipImageDownloadService {
  suspend fun loadImage(url: String): ByteArray {
    val target =
      try {
        URL(url)
      } catch (error: MalformedURLException) {
        throw ClipImageDownloadError.UnsupportedURL
      }
    val scheme = target.protocol.lowercase()
    if (scheme != "http" && scheme != "https") throw ClipImageDownloadError.UnsupportedURL
    return withTimeoutOrNull(RESOURCE_TIMEOUT_MILLISECONDS) {
      runInterruptible(Dispatchers.IO) { read(target) }
    } ?: throw ClipImageDownloadError.RequestFailed
  }

  private fun read(target: URL): ByteArray {
    try {
      val connection = target.openConnection() as HttpURLConnection
      try {
        connection.useCaches = false
        connection.connectTimeout = REQUEST_TIMEOUT_MILLISECONDS
        connection.readTimeout = REQUEST_TIMEOUT_MILLISECONDS
        if (connection.responseCode !in 200..299) throw ClipImageDownloadError.InvalidResponse
        if (connection.contentType?.trim()?.lowercase()?.startsWith("image/") != true) throw ClipImageDownloadError.NotImage
        if (MAXIMUM_BYTE_COUNT < connection.contentLengthLong) throw ClipImageDownloadError.TooLarge
        return connection.inputStream.use { input ->
          val output = ByteArrayOutputStream()
          val buffer = ByteArray(BUFFER_BYTE_COUNT)
          while (true) {
            val count = input.read(buffer)
            if (count < 0) break
            // 최대치를 넘는 바이트는 보관하지 않음
            if (MAXIMUM_BYTE_COUNT < output.size() + count) throw ClipImageDownloadError.TooLarge
            output.write(buffer, 0, count)
          }
          output.toByteArray()
        }
      } finally {
        connection.disconnect()
      }
    } catch (error: IOException) {
      throw ClipImageDownloadError.RequestFailed
    }
  }

  private companion object {
    // 내려받을 수 있는 본문의 최대 바이트 수
    const val MAXIMUM_BYTE_COUNT = 20L * 1024 * 1024
    const val BUFFER_BYTE_COUNT = 64 * 1024
    const val REQUEST_TIMEOUT_MILLISECONDS = 10_000
    const val RESOURCE_TIMEOUT_MILLISECONDS = 20_000L
  }
}
