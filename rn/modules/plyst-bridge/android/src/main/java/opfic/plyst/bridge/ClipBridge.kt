package opfic.plyst.bridge

import java.util.UUID
import kotlinx.coroutines.Job
import kotlinx.coroutines.MainScope
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.launch

data class ClipBridgeRecord(
  val id: UUID,
  val text: String?,
  val image: Image?,
  val name: String?,
  val memo: String?,
  val pinnedAt: Double?,
  val isWebLink: Boolean,
  val createdAt: Double,
  val lastUsedAt: Double?,
) {
  data class Image(
    val byteCount: Int,
    val contentType: String,
    val pixelWidth: Int,
    val pixelHeight: Int,
  )
}

data class ClipBridgeChange(
  val kind: Kind,
  val id: UUID,
) {
  enum class Kind(val wire: String) {
    INSERTED("inserted"),
    UPDATED("updated"),
    DELETED("deleted"),
  }
}

enum class ClipBridgeCopyResult(val wire: String) {
  COPIED("copied"),
  COPIED_WITHOUT_LAST_USED_AT("copiedWithoutLastUsedAt"),
  WRITE_NOT_OBSERVED("writeNotObserved"),
}

enum class ClipBridgePhotoSaveResult(val wire: String) {
  SAVED("saved"),
  DENIED("denied"),
  RESTRICTED("restricted"),
}

enum class ClipBridgeClipboardSaveResult(val wire: String) {
  SAVED("saved"),
  EMPTY("empty"),
  UNSUPPORTED("unsupported"),
  ACCESS_FAILED("accessFailed"),
  INVALID_IMAGE("invalidImage"),
}

enum class ClipBridgeError(val code: String) {
  INVALID_ID("E_INVALID_ID"),
  UNAVAILABLE("E_UNAVAILABLE"),
  SAVE_FAILED("E_SAVE_FAILED"),
  COPY_FAILED("E_COPY_FAILED"),
  WRITE_FAILED("E_WRITE_FAILED"),
  READ_FAILED("E_READ_FAILED"),
  CORRUPTED_DATA("E_CORRUPTED_DATA"),
  PHOTO_SAVE_FAILED("E_PHOTO_SAVE_FAILED"),
  IMAGE_UNAVAILABLE("E_IMAGE_UNAVAILABLE"),
}

class ClipBridgeException(val error: ClipBridgeError) : Exception(error.code)

// 호스트가 구현하는 클립 저장소 진입점
// 구현은 CancellationException을 다른 오류로 바꾸지 않고 그대로 전파
interface ClipBridgeProvider {
  fun changes(): Flow<ClipBridgeChange>

  suspend fun getClipImagePreview(id: UUID): String?

  suspend fun getClipThumbnail(
    id: UUID,
    maximumPixelDimension: Int,
  ): String?

  suspend fun saveClipImageToPhotos(id: UUID): ClipBridgePhotoSaveResult?

  suspend fun clip(id: UUID): ClipBridgeRecord?

  suspend fun saveCurrentClipboard(): ClipBridgeClipboardSaveResult

  suspend fun clips(): List<ClipBridgeRecord>

  suspend fun searchHistory(): List<String>

  suspend fun recordSearchTerm(term: String): List<String>?

  suspend fun removeSearchTerm(term: String): List<String>

  suspend fun removeAllSearchTerms()

  suspend fun updateClip(
    id: UUID,
    name: String?,
    memo: String?,
    isPinned: Boolean,
  ): ClipBridgeRecord?

  suspend fun deleteClip(id: UUID)

  suspend fun copyClip(id: UUID): ClipBridgeCopyResult?
}

// 호스트가 등록한 provider와 JavaScript 이벤트 전송 함수를 메인 스레드에서 보관
object ClipBridge {
  private val scope = MainScope()
  internal var provider: ClipBridgeProvider? = null
    private set
  private var changesJob: Job? = null
  private var registration: Pair<UUID, (String, String) -> Unit>? = null

  // 메인 스레드에서 호출
  fun register(provider: ClipBridgeProvider) {
    changesJob?.cancel()
    this.provider = provider
    changesJob = scope.launch {
      provider.changes().collect { change ->
        registration?.second?.invoke(change.kind.wire, wireID(change.id))
      }
    }
  }

  internal fun register(
    id: UUID,
    emit: (String, String) -> Unit,
  ) {
    registration = id to emit
  }

  internal fun unregister(id: UUID) {
    if (registration?.first == id) registration = null
  }

  // 메인 스레드에서 호출
  fun unregister() {
    changesJob?.cancel()
    changesJob = null
    provider = null
  }

  private val uuidPattern =
    Regex("^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$")

  // Swift uuidString과 같은 대문자 형식
  internal fun wireID(id: UUID) = id.toString().uppercase()

  // UUID.fromString은 자릿수가 모자란 문자열도 받아서 Swift UUID(uuidString:)과 같은 형식만 허용
  internal fun parseWireID(value: String): UUID? =
    if (uuidPattern.matches(value)) UUID.fromString(value) else null
}
