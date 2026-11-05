package opfic.plyst.bridge

import java.util.UUID

// 호스트가 클립보드 저장 요청을 전달하는 진입점
// ready()에서 보관된 저장 요청을 전달
// 메인 스레드에서만 호출
object HomeBridge {
  private var registration: Pair<UUID, () -> Unit>? = null
  private var isClipboardSaveRequested = false

  internal fun register(
    id: UUID,
    requestSave: () -> Unit,
  ) {
    registration = id to requestSave
    if (isClipboardSaveRequested) {
      isClipboardSaveRequested = false
      requestSave()
    }
  }

  // 호스트가 클립보드 저장을 요청
  // ready() 전에는 요청 하나를 만료 없이 보관
  fun requestClipboardSave() {
    val requestSave = registration?.second
    if (requestSave == null) {
      isClipboardSaveRequested = true
      return
    }
    requestSave()
  }

  internal fun unregister(id: UUID) {
    if (registration?.first == id) registration = null
  }

  // JavaScript 런타임이 Activity보다 오래 살아 이전 Home의 등록이 남음
  // 새 Home이 ready()를 부를 때까지 요청을 보관하도록 등록을 비움
  fun clearRegistration() {
    registration = null
  }
}
