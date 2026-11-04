package opfic.plyst.bridge

import com.facebook.react.uimanager.ThemedReactContext
import com.facebook.react.uimanager.annotations.ReactProp
import com.facebook.react.views.view.ReactViewGroup
import com.facebook.react.views.view.ReactViewManager

// 테두리, 배경, overflow 같은 View props는 ReactViewManager가 처리
class PlystSearchTransitionManager : ReactViewManager() {
  override fun getName() = NAME

  override fun createViewInstance(context: ThemedReactContext): ReactViewGroup = PlystSearchTransitionView(context)

  @ReactProp(name = "effect")
  fun setEffect(
    view: ReactViewGroup,
    effect: String?,
  ) {
    (view as PlystSearchTransitionView).setEffect(effect)
  }

  @ReactProp(name = "isPresented", defaultBoolean = false)
  fun setIsPresented(
    view: ReactViewGroup,
    isPresented: Boolean,
  ) {
    (view as PlystSearchTransitionView).setRequestedIsPresented(isPresented)
  }

  override fun onAfterUpdateTransaction(view: ReactViewGroup) {
    super.onAfterUpdateTransaction(view)
    (view as PlystSearchTransitionView).finalizeUpdates()
  }

  override fun prepareToRecycleView(
    reactContext: ThemedReactContext,
    view: ReactViewGroup,
  ): ReactViewGroup? {
    (view as PlystSearchTransitionView).resetForRecycle()
    return super.prepareToRecycleView(reactContext, view)
  }

  override fun getExportedCustomDirectEventTypeConstants(): Map<String, Any> =
    (super.getExportedCustomDirectEventTypeConstants() ?: emptyMap()) +
      mapOf(PlystSearchTransitionView.EVENT_NAME to mapOf("registrationName" to "onTransitionEnd"))

  companion object {
    const val NAME = "PlystSearchTransition"
  }
}
