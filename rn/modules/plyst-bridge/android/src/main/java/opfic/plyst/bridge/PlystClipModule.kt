package opfic.plyst.bridge

import android.os.Handler
import android.os.Looper
import com.facebook.react.bridge.Arguments
import com.facebook.react.bridge.Promise
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.bridge.WritableMap
import java.util.UUID
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch

// JavaScript 호출을 메인 스레드의 ClipBridge provider로 전달
// 무효화된 뒤 끝난 호출의 결과는 Promise에 전달하지 않음
class PlystClipModule(context: ReactApplicationContext) : NativePlystClipSpec(context) {
  private val id = UUID.randomUUID()
  private val main = Handler(Looper.getMainLooper())
  private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

  // 메인 스레드에서만 읽고 씀
  private var isInvalidated = false

  override fun getName() = NAME

  override fun ready() {
    main.post {
      if (isInvalidated) return@post
      ClipBridge.register(id) { kind, clipID ->
        val change = Arguments.createMap()
        change.putString("kind", kind)
        change.putString("id", clipID)
        emitOnClipChange(change)
      }
    }
  }

  override fun getClip(
    id: String,
    promise: Promise,
  ) = execute(id, promise, ClipBridgeError.READ_FAILED, { provider, clipID ->
    provider.clip(clipID)
  }) { record -> record?.let(::map) }

  override fun getClips(promise: Promise) =
    execute(promise, ClipBridgeError.READ_FAILED, { provider -> provider.clips() }) { records ->
      Arguments.createArray().apply { records.forEach { pushMap(map(it)) } }
    }

  override fun getSearchHistory(promise: Promise) =
    execute(promise, ClipBridgeError.READ_FAILED, { provider -> provider.searchHistory() }, ::array)

  override fun recordSearchTerm(
    term: String,
    promise: Promise,
  ) = execute(promise, ClipBridgeError.WRITE_FAILED, { provider ->
    provider.recordSearchTerm(term)
  }) { terms -> terms?.let(::array) }

  override fun removeSearchTerm(
    term: String,
    promise: Promise,
  ) = execute(promise, ClipBridgeError.WRITE_FAILED, { provider ->
    provider.removeSearchTerm(term)
  }, ::array)

  override fun removeAllSearchTerms(promise: Promise) =
    execute(promise, ClipBridgeError.WRITE_FAILED, { provider ->
      provider.removeAllSearchTerms()
    }) { null }

  override fun saveCurrentClipboard(promise: Promise) =
    execute(promise, ClipBridgeError.SAVE_FAILED, { provider ->
      provider.saveCurrentClipboard()
    }) { result -> result.wire }

  override fun getClipImagePreview(
    id: String,
    promise: Promise,
  ) = execute(id, promise, ClipBridgeError.IMAGE_UNAVAILABLE, { provider, clipID ->
    provider.getClipImagePreview(clipID)
  }) { it }

  override fun getClipThumbnail(
    id: String,
    maximumPixelDimension: Double,
    promise: Promise,
  ) {
    val dimension = maximumPixelDimension.toInt()
    if (dimension.toDouble() != maximumPixelDimension || dimension <= 0) {
      promise.reject(ClipBridgeError.IMAGE_UNAVAILABLE.code, ClipBridgeError.IMAGE_UNAVAILABLE.code)
      return
    }
    execute(id, promise, ClipBridgeError.IMAGE_UNAVAILABLE, { provider, clipID ->
      provider.getClipThumbnail(clipID, dimension)
    }) { it }
  }

  override fun saveClipImageToPhotos(
    id: String,
    promise: Promise,
  ) = execute(id, promise, ClipBridgeError.PHOTO_SAVE_FAILED, { provider, clipID ->
    provider.saveClipImageToPhotos(clipID)
  }) { result -> result?.wire }

  override fun updateClip(
    id: String,
    name: String?,
    memo: String?,
    isPinned: Boolean,
    promise: Promise,
  ) = execute(id, promise, ClipBridgeError.WRITE_FAILED, { provider, clipID ->
    provider.updateClip(clipID, name, memo, isPinned)
  }) { record -> record?.let(::map) }

  override fun deleteClip(
    id: String,
    promise: Promise,
  ) = execute(id, promise, ClipBridgeError.WRITE_FAILED, { provider, clipID ->
    provider.deleteClip(clipID)
  }) { null }

  override fun copyClip(
    id: String,
    promise: Promise,
  ) = execute(id, promise, ClipBridgeError.COPY_FAILED, { provider, clipID ->
    provider.copyClip(clipID)
  }) { result -> result?.wire }

  override fun invalidate() {
    super.invalidate()
    main.post {
      isInvalidated = true
      ClipBridge.unregister(id)
      scope.cancel()
    }
  }

  private fun <T> execute(
    identifier: String,
    promise: Promise,
    fallback: ClipBridgeError,
    operation: suspend (ClipBridgeProvider, UUID) -> T,
    resolve: (T) -> Any?,
  ) = execute(promise, fallback, { provider ->
    val clipID = parseWireID(identifier) ?: throw ClipBridgeException(ClipBridgeError.INVALID_ID)
    operation(provider, clipID)
  }, resolve)

  private fun <T> execute(
    promise: Promise,
    fallback: ClipBridgeError,
    operation: suspend (ClipBridgeProvider) -> T,
    resolve: (T) -> Any?,
  ) {
    scope.launch {
      if (isInvalidated) return@launch
      val code =
        try {
          val provider = ClipBridge.provider ?: throw ClipBridgeException(ClipBridgeError.UNAVAILABLE)
          val value = operation(provider)
          if (isInvalidated) return@launch
          promise.resolve(resolve(value))
          return@launch
        } catch (error: CancellationException) {
          throw error
        } catch (error: ClipBridgeException) {
          error.error.code
        } catch (error: Exception) {
          fallback.code
        }
      if (isInvalidated) return@launch
      promise.reject(code, code)
    }
  }

  private fun array(terms: List<String>) =
    Arguments.createArray().apply { terms.forEach(::pushString) }

  private fun map(record: ClipBridgeRecord): WritableMap =
    Arguments.createMap().apply {
      putString("id", wireID(record.id))
      putString("text", record.text)
      val image = record.image
      if (image == null) {
        putNull("image")
      } else {
        putMap(
          "image",
          Arguments.createMap().apply {
            putInt("byteCount", image.byteCount)
            putString("contentType", image.contentType)
            putInt("pixelWidth", image.pixelWidth)
            putInt("pixelHeight", image.pixelHeight)
          },
        )
      }
      putString("name", record.name)
      putString("memo", record.memo)
      putNullableDouble("pinnedAt", record.pinnedAt)
      putBoolean("isWebLink", record.isWebLink)
      putDouble("createdAt", record.createdAt)
      putNullableDouble("lastUsedAt", record.lastUsedAt)
    }

  private fun WritableMap.putNullableDouble(
    key: String,
    value: Double?,
  ) {
    if (value == null) putNull(key) else putDouble(key, value)
  }

  companion object {
    const val NAME = "PlystClip"
  }
}
