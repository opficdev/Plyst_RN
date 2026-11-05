package opfic.plyst.host.app

import android.app.Activity
import android.content.res.Configuration
import android.os.Bundle
import android.util.Log
import android.view.ViewGroup
import androidx.core.view.ViewCompat
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import kotlin.coroutines.cancellation.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import opfic.plyst.host.feature.share.ShareStatus
import opfic.plyst.host.feature.share.ShareStatusView
import opfic.plyst.host.service.clip.share.ClipShareItem
import opfic.plyst.host.service.clip.share.ClipShareSaveResult

// 공유 시트로 받은 항목 하나를 저장하고 결과를 표시
// iOS ShareViewController와 ShareReactor를 합친 화면으로 상태 세 개만 직접 소유
// 저장소는 앱과 같은 프로세스의 구성을 쓰고 공유 수신함은 두지 않음
class ShareActivity : Activity() {
  private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
  private var status = ShareStatus.SAVING
  private var isSaving = false
  private var didFinish = false
  private lateinit var item: ClipShareItem
  private lateinit var statusView: ShareStatusView

  override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)
    // 프로세스가 복원되면 이미 저장한 항목을 또 저장할 수 있으므로 저장하지 않고 닫음
    if (savedInstanceState != null) {
      finish()
      return
    }
    WindowCompat.setDecorFitsSystemWindows(window, false)
    item = ClipShareItem.of(intent)
    showStatusView()
    save()
  }

  // Activity를 다시 만들지 않으므로 화면 모양이 바뀌면 색을 새로 읽도록 View만 다시 만듦
  override fun onConfigurationChanged(newConfig: Configuration) {
    super.onConfigurationChanged(newConfig)
    if (::statusView.isInitialized) showStatusView()
  }

  override fun onDestroy() {
    scope.cancel()
    super.onDestroy()
  }

  private fun showStatusView() {
    statusView = ShareStatusView(this, onRetry = ::save, onCancel = ::finish)
    setContentView(statusView)
    ViewCompat.setOnApplyWindowInsetsListener(statusView) { view, insets ->
      val bars = insets.getInsets(WindowInsetsCompat.Type.systemBars() or WindowInsetsCompat.Type.displayCutout())
      (view.layoutParams as ViewGroup.MarginLayoutParams).topMargin = bars.top
      view.setPadding(bars.left, 0, bars.right, bars.bottom)
      view.requestLayout()
      insets
    }
    ViewCompat.requestApplyInsets(statusView)
    statusView.setStatus(status)
  }

  private fun save() {
    if (isSaving || status == ShareStatus.COMPLETED) return
    isSaving = true
    render(ShareStatus.SAVING)
    scope.launch {
      val result =
        try {
          val saved = HostLifecycle.shareService()?.save(item) is ClipShareSaveResult.Saved
          if (saved) ShareStatus.COMPLETED else ShareStatus.FAILED
        } catch (error: CancellationException) {
          throw error
        } catch (error: Exception) {
          Log.e(TAG, "공유 저장 실패: ${error.javaClass.simpleName}")
          ShareStatus.FAILED
        }
      isSaving = false
      render(result)
    }
  }

  private fun render(status: ShareStatus) {
    this.status = status
    statusView.setStatus(status)
    if (status != ShareStatus.COMPLETED || didFinish) return
    didFinish = true
    scope.launch {
      delay(COMPLETION_DELAY_MILLISECONDS)
      finish()
    }
  }

  private companion object {
    const val TAG = "ShareActivity"

    // 저장 완료를 보여 준 뒤 닫기까지의 시간
    const val COMPLETION_DELAY_MILLISECONDS = 2_000L
  }
}
