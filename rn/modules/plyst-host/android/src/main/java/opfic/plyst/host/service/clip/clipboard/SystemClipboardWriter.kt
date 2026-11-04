package opfic.plyst.host.service.clip.clipboard

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import androidx.core.content.FileProvider
import java.io.File
import java.util.UUID
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import opfic.plyst.host.service.clip.image.ClipImageContentType

// 쓰기 후 기록된 표현을 다시 읽어 확인
// 이미지는 FileProvider URI로 공유하며 직전에 쓴 이미지 파일만 남김
class SystemClipboardWriter(private val context: Context) : ClipboardWriter {
  override suspend fun write(content: ClipboardWriteContent): ClipboardWriteResult =
    when (content) {
      is ClipboardWriteContent.Text ->
        withContext(Dispatchers.Main) {
          val clipboard = context.getSystemService(ClipboardManager::class.java)
          clipboard.setPrimaryClip(ClipData.newPlainText(LABEL, content.text))
          val written = clipboard.primaryClip?.takeIf { 0 < it.itemCount }?.getItemAt(0)?.text?.toString()
          if (written == content.text) ClipboardWriteResult.OBSERVED else ClipboardWriteResult.NOT_OBSERVED
        }
      is ClipboardWriteContent.Image -> {
        val file =
          withContext(Dispatchers.IO) {
            val directory = File(context.cacheDir, DIRECTORY)
            directory.listFiles()?.forEach { it.delete() }
            directory.mkdirs()
            val extension = ClipImageContentType.fileExtension(content.contentType)
            File(directory, "${UUID.randomUUID()}.$extension").apply { writeBytes(content.data) }
          }
        withContext(Dispatchers.Main) {
          val clipboard = context.getSystemService(ClipboardManager::class.java)
          val uri = FileProvider.getUriForFile(context, "${context.packageName}$AUTHORITY_SUFFIX", file)
          clipboard.setPrimaryClip(ClipData.newUri(context.contentResolver, LABEL, uri))
          val written = clipboard.primaryClip?.takeIf { 0 < it.itemCount }?.getItemAt(0)?.uri
          if (written == uri) ClipboardWriteResult.OBSERVED else ClipboardWriteResult.NOT_OBSERVED
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
