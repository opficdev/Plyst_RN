package opfic.plyst.host.app

import android.app.Activity
import android.app.Application
import android.util.Log
import java.lang.ref.WeakReference
import opfic.plyst.bridge.ClipBridge

// 구성과 어댑터 등록을 앱 프로세스 수명에 맞춰 한 번만 수행
// JavaScript 런타임이 Activity보다 오래 살아 Activity 수명에 묶지 않음
// 구성에 실패하면 iOS처럼 Activity에 다시 시도 화면을 띄움
internal object HostLifecycle {
  private var application: Application? = null
  private var composition: HostComposition? = null
  private var activity = WeakReference<Activity>(null)

  fun onApplicationCreate(application: Application) {
    this.application = application
    configure()
  }

  fun onActivityCreate(activity: Activity) {
    this.activity = WeakReference(activity)
    if (composition == null) showStartupFailure(activity)
  }

  fun onActivityDestroy(activity: Activity) {
    if (this.activity.get() === activity) this.activity = WeakReference(null)
  }

  private fun configure() {
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
