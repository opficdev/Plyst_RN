package opfic.plyst.host.service.clip.clipboard

import android.content.ClipboardManager
import android.content.Context
import java.io.IOException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import opfic.plyst.host.model.ClipContent

// 첫 항목의 형식을 확인하고 읽음
// 변경을 감시하거나 읽기를 재시도하지 않음
// Android 10부터 클립보드는 창 포커스를 가진 앱만 읽을 수 있음
class SystemClipboardReader(private val context: Context) : ClipboardReader {
  override suspend fun read(): ClipboardReadResult {
    val item =
      withContext(Dispatchers.Main) {
        val clipboard = context.getSystemService(ClipboardManager::class.java)
        clipboard?.primaryClip?.takeIf { 0 < it.itemCount }?.getItemAt(0)
      } ?: return ClipboardReadResult.Empty
    // 첫 항목의 이미지 표현을 우선 선택하고 읽기 실패 시 텍스트로 대체하지 않음
    val uri = item.uri
    if (uri != null && context.contentResolver.getType(uri)?.startsWith("image/") == true) {
      return withContext(Dispatchers.IO) {
        try {
          context.contentResolver.openInputStream(uri)?.use { ClipboardReadResult.Image(it.readBytes()) }
            ?: ClipboardReadResult.AccessFailed
        } catch (error: IOException) {
          ClipboardReadResult.AccessFailed
        } catch (error: SecurityException) {
          ClipboardReadResult.AccessFailed
        }
      }
    }
    val text = item.text?.toString()
    if (text != null) return if (ClipContent.Text(text).isValid) ClipboardReadResult.Text(text) else ClipboardReadResult.Empty
    // iOS가 URL 항목을 문자열로 저장하는 것과 같이 이미지가 아닌 URI는 문자열로 저장
    if (uri != null) return ClipboardReadResult.Text(uri.toString())
    return ClipboardReadResult.Unsupported
  }
}
