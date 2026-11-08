package opfic.plyst

import android.content.Intent
import android.os.Build
import android.os.Bundle

import com.facebook.react.ReactActivity
import com.facebook.react.ReactActivityDelegate
import com.facebook.react.defaults.DefaultNewArchitectureEntryPoint.fabricEnabled
import com.facebook.react.defaults.DefaultReactActivityDelegate

import expo.modules.ReactActivityDelegateWrapper
import opfic.plyst.host.app.HostLifecycle

class MainActivity : ReactActivity() {
  override fun onCreate(savedInstanceState: Bundle?) {
    // 시작 화면 테마에서 배경과 시스템 바 색을 정하는 AppTheme으로 onCreate 전에 전환
    setTheme(R.style.AppTheme);
    if (savedInstanceState != null) intent = android.content.Intent(intent).setData(null)
    super.onCreate(null)
    // Expo 활동 리스너가 부르던 자리와 같은 super.onCreate 직후
    HostLifecycle.onActivityCreate(this)
  }

  // Expo 활동 리스너처럼 React Native보다 먼저 Intent를 받음
  override fun onNewIntent(intent: Intent) {
    HostLifecycle.onActivityNewIntent(intent)
    super.onNewIntent(intent)
  }

  override fun onDestroy() {
    HostLifecycle.onActivityDestroy(this)
    super.onDestroy()
  }

  // index.ts가 등록한 루트 이름이며 iOS SceneComposition이 여는 moduleName과 같음
  override fun getMainComponentName(): String = "AppRoot"

  // New Architecture 여부를 fabricEnabled 하나로 정하는 DefaultReactActivityDelegate를 Expo 래퍼로 감쌈
  override fun createReactActivityDelegate(): ReactActivityDelegate {
    return ReactActivityDelegateWrapper(
          this,
          BuildConfig.IS_NEW_ARCHITECTURE_ENABLED,
          object : DefaultReactActivityDelegate(
              this,
              mainComponentName,
              fabricEnabled
          ){})
  }

  // 루트 Activity의 뒤로 가기를 Android S처럼 종료 대신 백그라운드 이동으로 맞춤
  override fun invokeDefaultOnBackPressed() {
      if (Build.VERSION.SDK_INT <= Build.VERSION_CODES.R) {
          if (!moveTaskToBack(false)) {
              // 루트가 아닌 Activity는 기본 동작으로 종료
              super.invokeDefaultOnBackPressed()
          }
          return
      }

      // Android S 이후의 기본 동작은 Activity.moveTaskToBack보다 하는 일이 많아 그대로 사용
      super.invokeDefaultOnBackPressed()
  }
}
