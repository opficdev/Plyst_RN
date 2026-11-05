package opfic.plyst.host.model

import java.net.URI

// 앱 밖에서 앱으로 진입할 때 사용하는 URL 호출 형식
// 위젯이 만들고 앱이 해석
enum class AppLink(val url: String) {
  SAVE_CLIPBOARD("plystrn://clipboard/save"),
  ;

  companion object {
    fun of(url: String?): AppLink? {
      val uri = url?.let { runCatching { URI(it) }.getOrNull() } ?: return null
      if (uri.scheme != "plystrn" || uri.host != "clipboard" || uri.path != "/save") return null
      return SAVE_CLIPBOARD
    }
  }
}
