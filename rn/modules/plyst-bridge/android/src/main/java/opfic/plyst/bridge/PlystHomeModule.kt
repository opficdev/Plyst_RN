package opfic.plyst.bridge

import com.facebook.react.bridge.ReactApplicationContext

// Android에는 클립보드 저장을 요청하는 위젯과 앱 링크가 없어 onClipboardSaveRequest를 보내지 않음
class PlystHomeModule(context: ReactApplicationContext) : NativePlystHomeSpec(context) {
  override fun getName() = NAME

  override fun ready() = Unit

  // iPhone Duo는 iOS 기기라서 Android에서는 항상 false
  override fun isDuoDevice() = false

  companion object {
    const val NAME = "PlystHome"
  }
}
