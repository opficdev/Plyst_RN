package opfic.plyst.host.adapter.clip

import java.util.concurrent.CopyOnWriteArraySet
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.channels.SendChannel
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.buffer
import kotlinx.coroutines.flow.callbackFlow
import opfic.plyst.core.ClipChangeListener
import opfic.plyst.core.ClipChangeValue
import opfic.plyst.host.model.clip
import opfic.plyst.host.model.uuid

// 코어의 변경 알림을 구독자에게 전달
// 코어가 이 객체를 강한 참조로 보관하므로 어댑터를 참조하지 않음
// 연결 잠금을 쥔 채 호출되므로 코어를 호출하거나 대기하지 않음
internal class ClipStorageSubscribers : ClipChangeListener {
  private val subscriptions = CopyOnWriteArraySet<SendChannel<ClipStorageEvent>>()

  override fun changed(change: ClipChangeValue) {
    val event = event(change) ?: return
    subscriptions.forEach { it.trySend(event) }
  }

  fun changes(): Flow<ClipStorageEvent> =
    callbackFlow {
      subscriptions.add(channel)
      awaitClose { subscriptions.remove(channel) }
    }.buffer(Channel.UNLIMITED)

  // 코어가 검사한 식별자라 변환은 실패하지 않음
  private fun event(change: ClipChangeValue) =
    when (change) {
      is ClipChangeValue.Inserted -> change.clip.clip?.let(ClipStorageEvent::Inserted)
      is ClipChangeValue.Updated -> change.clip.clip?.let(ClipStorageEvent::Updated)
      is ClipChangeValue.Deleted -> change.id.uuid?.let(ClipStorageEvent::Deleted)
    }
}
