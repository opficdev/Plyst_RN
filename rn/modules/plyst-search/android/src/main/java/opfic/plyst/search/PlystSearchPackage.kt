package opfic.plyst.search

import com.facebook.react.BaseReactPackage
import com.facebook.react.bridge.NativeModule
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.module.model.ReactModuleInfoProvider

// Codegen과 autolinking이 이 패키지를 라이브러리로 인식하기 위한 클래스
// 모듈은 C++ autolinking이 만들므로 Kotlin 모듈 없음
class PlystSearchPackage : BaseReactPackage() {
  override fun getModule(
    name: String,
    reactContext: ReactApplicationContext,
  ): NativeModule? = null

  override fun getReactModuleInfoProvider() = ReactModuleInfoProvider { emptyMap() }
}
