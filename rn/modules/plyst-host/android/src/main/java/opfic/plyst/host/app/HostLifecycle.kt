package opfic.plyst.host.app

import android.app.Activity
import android.app.Application
import android.content.Intent
import android.util.Log
import java.lang.ref.WeakReference
import opfic.plyst.bridge.ClipBridge
import opfic.plyst.bridge.HomeBridge
import opfic.plyst.host.model.AppLink
import opfic.plyst.host.service.clip.share.ClipShareService

// 구성과 어댑터 등록을 앱 프로세스 수명에 맞춰 한 번만 수행
// JavaScript 런타임이 Activity보다 오래 살아 Activity 수명에 묶지 않음
// 구성에 실패하면 iOS처럼 Activity에 다시 시도 화면을 띄움
internal object HostLifecycle {
  private var application: Application? = null
  private var composition: HostComposition? = null
  private var activity = WeakReference<Activity>(null)
  private var isClipboardSaveRequested = false

  fun onApplicationCreate(application: Application) {
    this.application = application
    configure()
  }

  fun onActivityCreate(activity: Activity) {
    this.activity = WeakReference(activity)
    HomeBridge.clearRegistration()
    if (composition == null) showStartupFailure(activity)
    request(activity.intent)
    // 클립보드는 창 포커스를 가진 앱만 읽을 수 있어 onResume이 아니라 창 포커스를 기다림
    activity.window.decorView.viewTreeObserver.addOnWindowFocusChangeListener { hasFocus ->
      if (hasFocus) saveClipboardIfRequested()
    }
  }

  fun onActivityNewIntent(intent: Intent) {
    request(intent)
    if (activity.get()?.hasWindowFocus() == true) saveClipboardIfRequested()
  }

  fun onActivityDestroy(activity: Activity) {
    if (this.activity.get() === activity) this.activity = WeakReference(null)
  }

  // 구성에 실패한 상태면 iOS 공유 화면의 prepare처럼 부를 때마다 다시 구성
  fun shareService(): ClipShareService? {
    configure()
    return composition?.shares
  }

  // ClipCoreAdapter는 인스턴스 하나를 전제로 하므로 이미 구성했으면 만들지 않음
  private fun configure() {
    if (composition != null) return
    val application = application ?: return
    try {
      val composition = HostComposition(application) { activity.get() }
      this.composition = composition
      ClipBridge.register(composition.makeAdapter())
      composition.startPendingCleanupRecovery()
    } catch (error: Exception) {
      Log.e(TAG, "기록 화면 초기화 실패: ${error.javaClass.simpleName}")
      ClipBridge.unregister()
      composition = null
    }
  }

  // 최근 앱에서 다시 열면 시스템이 처음 Intent를 다시 전달하므로 요청으로 보지 않음
  private fun request(intent: Intent?) {
    if (intent == null || intent.flags and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY != 0) return
    if (AppLink.of(intent.dataString) == AppLink.SAVE_CLIPBOARD) isClipboardSaveRequested = true
  }

  // 처리할 수 없는 상태에서 요청이 남아 이후 포커스에 실행되지 않도록 항상 요청을 비움
  private fun saveClipboardIfRequested() {
    if (!isClipboardSaveRequested) return
    isClipboardSaveRequested = false
    if (composition != null) HomeBridge.requestClipboardSave()
  }

  // 다시 구성에 성공하면 Activity를 새로 만들어 React Native 화면을 다시 붙임
  private fun showStartupFailure(activity: Activity) {
    activity.setContentView(
      StartupFailureView(activity) {
        configure()
        if (composition != null) activity.recreate()
      },
    )
  }

  private const val TAG = "HostLifecycle"
}
