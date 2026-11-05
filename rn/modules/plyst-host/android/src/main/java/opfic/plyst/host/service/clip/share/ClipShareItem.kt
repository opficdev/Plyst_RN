package opfic.plyst.host.service.clip.share

import android.content.Intent
import android.net.Uri
import androidx.core.content.IntentCompat

// 공유 시트로 받은 항목 하나
class ClipShareItem(
  val stream: Uri?,
  val type: String?,
  val text: String?,
  title: String?,
) {
  // 앞뒤 공백을 제거한 공유 항목 제목
  // 공백뿐이면 null
  val title = title?.trim()?.takeIf { it.isNotEmpty() }

  companion object {
    fun of(intent: Intent) =
      ClipShareItem(
        stream = IntentCompat.getParcelableExtra(intent, Intent.EXTRA_STREAM, Uri::class.java),
        type = intent.type,
        text = intent.getCharSequenceExtra(Intent.EXTRA_TEXT)?.toString(),
        title = intent.getStringExtra(Intent.EXTRA_SUBJECT) ?: intent.getCharSequenceExtra(Intent.EXTRA_TITLE)?.toString(),
      )
  }
}
