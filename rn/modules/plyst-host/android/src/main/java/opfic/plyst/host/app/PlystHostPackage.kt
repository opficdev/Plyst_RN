package opfic.plyst.host.app

import android.app.Activity
import android.app.Application
import android.content.Context
import android.os.Bundle
import expo.modules.core.interfaces.ApplicationLifecycleListener
import expo.modules.core.interfaces.Package
import expo.modules.core.interfaces.ReactActivityLifecycleListener

// Expo 자동 링크가 등록하는 진입점
class PlystHostPackage : Package {
  override fun createApplicationLifecycleListeners(context: Context): List<ApplicationLifecycleListener> =
    listOf(
      object : ApplicationLifecycleListener {
        override fun onCreate(application: Application) = HostLifecycle.onApplicationCreate(application)
      },
    )

  override fun createReactActivityLifecycleListeners(activityContext: Context): List<ReactActivityLifecycleListener> =
    listOf(
      object : ReactActivityLifecycleListener {
        override fun onCreate(
          activity: Activity,
          savedInstanceState: Bundle?,
        ) = HostLifecycle.onActivityCreate(activity)

        override fun onDestroy(activity: Activity) = HostLifecycle.onActivityDestroy(activity)
      },
    )
}
