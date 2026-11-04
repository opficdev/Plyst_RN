package opfic.plyst.bridge

import com.facebook.react.BaseReactPackage
import com.facebook.react.bridge.NativeModule
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.module.model.ReactModuleInfo
import com.facebook.react.module.model.ReactModuleInfoProvider
import com.facebook.react.uimanager.ViewManager

class PlystBridgePackage : BaseReactPackage() {
  override fun getModule(
    name: String,
    reactContext: ReactApplicationContext,
  ): NativeModule? =
    when (name) {
      PlystClipModule.NAME -> PlystClipModule(reactContext)
      PlystHomeModule.NAME -> PlystHomeModule(reactContext)
      else -> null
    }

  override fun getReactModuleInfoProvider() = ReactModuleInfoProvider {
    listOf(PlystClipModule.NAME, PlystHomeModule.NAME).associateWith { name ->
      ReactModuleInfo(
        name,
        name,
        false,
        false,
        false,
        true,
      )
    }
  }

  // iPhone Duo 전용 PlystNavigationBarButton은 Android에서 그리지 않아 등록하지 않음
  override fun createViewManagers(reactContext: ReactApplicationContext): List<ViewManager<*, *>> =
    listOf(PlystDetailBarButtonManager(), PlystSearchTransitionManager())
}
