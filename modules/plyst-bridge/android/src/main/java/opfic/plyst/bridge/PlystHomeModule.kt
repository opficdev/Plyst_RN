package opfic.plyst.bridge

import android.os.Handler
import android.os.Looper
import com.facebook.react.bridge.ReactApplicationContext
import java.util.UUID

class PlystHomeModule(context: ReactApplicationContext) : NativePlystHomeSpec(context) {
  private val id = UUID.randomUUID()
  private val main = Handler(Looper.getMainLooper())

  // 메인 스레드에서만 읽고 씀
  private var isInvalidated = false

  override fun getName() = NAME

  override fun ready() {
    main.post {
      if (isInvalidated) return@post
      HomeBridge.register(id) { emitOnClipboardSaveRequest() }
    }
  }

  // iPhone Duo는 iOS 기기라서 Android에서는 항상 false
  override fun isDuoDevice() = false

  override fun invalidate() {
    super.invalidate()
    main.post {
      isInvalidated = true
      HomeBridge.unregister(id)
    }
  }

  companion object {
    const val NAME = "PlystHome"
  }
}
