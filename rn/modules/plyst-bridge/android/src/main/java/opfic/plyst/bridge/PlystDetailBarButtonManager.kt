package opfic.plyst.bridge

import com.facebook.react.uimanager.SimpleViewManager
import com.facebook.react.uimanager.ThemedReactContext
import com.facebook.react.uimanager.annotations.ReactProp

class PlystDetailBarButtonManager : SimpleViewManager<PlystDetailBarButtonView>() {
  override fun getName() = NAME

  override fun createViewInstance(context: ThemedReactContext) = PlystDetailBarButtonView(context)

  @ReactProp(name = "icon")
  fun setIcon(
    view: PlystDetailBarButtonView,
    icon: String?,
  ) {
    view.setIcon(icon)
  }

  @ReactProp(name = "title")
  fun setTitle(
    view: PlystDetailBarButtonView,
    title: String?,
  ) {
    view.setTitle(title)
  }

  @ReactProp(name = "isEnabled", defaultBoolean = true)
  fun setIsEnabled(
    view: PlystDetailBarButtonView,
    isEnabled: Boolean,
  ) {
    view.isEnabled = isEnabled
  }

  override fun getExportedCustomDirectEventTypeConstants(): Map<String, Any> =
    (super.getExportedCustomDirectEventTypeConstants() ?: emptyMap()) +
      mapOf(PlystDetailBarButtonView.EVENT_NAME to mapOf("registrationName" to "onPress"))

  companion object {
    const val NAME = "PlystDetailBarButton"
  }
}
