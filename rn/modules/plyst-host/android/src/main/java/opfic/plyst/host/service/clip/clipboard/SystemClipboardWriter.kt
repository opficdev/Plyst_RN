package opfic.plyst.host.service.clip.clipboard

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import androidx.core.content.FileProvider
import java.io.File
import java.io.IOException
import java.util.UUID
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withContext
import opfic.plyst.core.ClipboardWriteException
import opfic.plyst.core.ClipboardWriteOutcome
import opfic.plyst.core.ClipboardWriteValue
import opfic.plyst.core.ClipboardWriter
import opfic.plyst.host.service.clip.image.ClipImageContentType

// 쓰기 후 기록된 표현을 다시 읽어 확인
// 이미지는 FileProvider URI로 공유하며 직전에 쓴 이미지 파일만 남김
// 코어가 Dispatchers.IO 계열 스레드에서 호출하므로 runBlocking이 Main 스레드를 막지 않음
// 오류는 쓰기를 시작하기 전에만 던지고 쓰기 이후에는 관찰 결과를 반환
class SystemClipboardWriter(private val context: Context) : ClipboardWriter {
  override fun write(content: ClipboardWriteValue): ClipboardWriteOutcome =
    try {
      runBlocking { written(content) }
    } catch (error: ClipboardWriteException) {
      throw error
    } catch (error: Exception) {
      throw ClipboardWriteException.Unexpected()
    }

  private suspend fun written(content: ClipboardWriteValue) =
    when (content) {
      is ClipboardWriteValue.Text ->
        withContext(Dispatchers.Main) {
          val clipboard = context.getSystemService(ClipboardManager::class.java)
          clipboard.setPrimaryClip(ClipData.newPlainText(LABEL, content.text))
          val written = clipboard.primaryClip?.takeIf { 0 < it.itemCount }?.getItemAt(0)?.text?.toString()
          if (written == content.text) ClipboardWriteOutcome.OBSERVED else ClipboardWriteOutcome.NOT_OBSERVED
        }
      is ClipboardWriteValue.Image -> {
        val file =
          withContext(Dispatchers.IO) {
            val directory = File(context.cacheDir, DIRECTORY)
            directory.listFiles()?.forEach { it.delete() }
            directory.mkdirs()
            val extension = ClipImageContentType.fileExtension(content.contentType)
            val target = File(directory, "${UUID.randomUUID()}.$extension")
            try {
              File(content.path).copyTo(target)
            } catch (error: IOException) {
              throw ClipboardWriteException.ReadFailed()
            }
          }
        withContext(Dispatchers.Main) {
          val clipboard = context.getSystemService(ClipboardManager::class.java)
          val uri = FileProvider.getUriForFile(context, "${context.packageName}$AUTHORITY_SUFFIX", file)
          clipboard.setPrimaryClip(ClipData.newUri(context.contentResolver, LABEL, uri))
          val written = clipboard.primaryClip?.takeIf { 0 < it.itemCount }?.getItemAt(0)?.uri
          if (written == uri) ClipboardWriteOutcome.OBSERVED else ClipboardWriteOutcome.NOT_OBSERVED
        }
      }
    }

  private companion object {
    const val LABEL = "Plyst"
    const val DIRECTORY = "clipboard"

    // AndroidManifest.xml의 provider authorities와 같은 값
    const val AUTHORITY_SUFFIX = ".plyst.clipboard"
  }
}
