package opfic.plyst.host.service.clip.download

import java.io.IOException
import java.net.HttpURLConnection
import java.net.MalformedURLException
import java.net.URL
import java.nio.file.Files
import java.nio.file.Paths
import java.nio.file.StandardOpenOption
import opfic.plyst.core.ClipCancellationSource
import opfic.plyst.core.ClipDownloadException
import opfic.plyst.core.ClipImageDownloader

// 코어가 정한 경로에 이미지 URL의 응답 본문을 최대 바이트 수 안에서 내려받음
// 요청은 GET 하나이며 쿠키와 캐시를 쓰지 않음
// 응답이 2xx일 때만 본문을 쓰고 응답 형식 판정과 검증과 저장은 코어가 맡음
// 코어가 호출한 IO 스레드에서 동기로 실행하고 덩어리마다 취소 상태와 전체 시간 제한을 확인
class SystemClipImageDownloader : ClipImageDownloader {
  // Content-Type 헤더 원문을 돌려줌
  override fun download(
    url: String,
    path: String,
    cancellation: ClipCancellationSource,
  ): String? {
    val target =
      try {
        URL(url)
      } catch (error: MalformedURLException) {
        throw ClipDownloadException.Failed()
      }
    val scheme = target.protocol.lowercase()
    if (scheme != "http" && scheme != "https") throw ClipDownloadException.Failed()
    val deadline = System.nanoTime() + RESOURCE_TIMEOUT_NANOSECONDS
    try {
      val connection = target.openConnection() as HttpURLConnection
      try {
        connection.useCaches = false
        connection.connectTimeout = REQUEST_TIMEOUT_MILLISECONDS
        connection.readTimeout = REQUEST_TIMEOUT_MILLISECONDS
        if (connection.responseCode !in 200..299) throw ClipDownloadException.Failed()
        if (MAXIMUM_BYTE_COUNT < connection.contentLengthLong) throw ClipDownloadException.Failed()
        // 이미 있는 항목과 링크를 따라가지 않고 새 파일만 만듦
        Files.newOutputStream(Paths.get(path), StandardOpenOption.CREATE_NEW, StandardOpenOption.WRITE).use { output ->
          connection.inputStream.use { input ->
            val buffer = ByteArray(BUFFER_BYTE_COUNT)
            var byteCount = 0L
            while (true) {
              if (cancellation.isCancelled()) throw ClipDownloadException.Cancelled()
              if (deadline < System.nanoTime()) throw ClipDownloadException.Failed()
              val count = input.read(buffer)
              if (count < 0) break
              byteCount += count
              // 최대치를 넘는 바이트는 보관하지 않음
              if (MAXIMUM_BYTE_COUNT < byteCount) throw ClipDownloadException.Failed()
              output.write(buffer, 0, count)
            }
          }
        }
        return connection.contentType
      } finally {
        connection.disconnect()
      }
    } catch (error: IOException) {
      throw if (cancellation.isCancelled()) ClipDownloadException.Cancelled() else ClipDownloadException.Failed()
    }
  }

  private companion object {
    // 내려받을 수 있는 본문의 최대 바이트 수
    const val MAXIMUM_BYTE_COUNT = 20L * 1024 * 1024
    const val BUFFER_BYTE_COUNT = 64 * 1024
    const val REQUEST_TIMEOUT_MILLISECONDS = 10_000
    const val RESOURCE_TIMEOUT_NANOSECONDS = 20_000_000_000L
  }
}
