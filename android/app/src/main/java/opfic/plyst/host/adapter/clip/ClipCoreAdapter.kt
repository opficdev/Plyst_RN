package opfic.plyst.host.adapter.clip

import android.util.Log
import java.io.File
import java.nio.ByteBuffer
import java.util.UUID
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.job
import kotlinx.coroutines.withContext
import opfic.plyst.core.ClipCancellationSource
import opfic.plyst.core.ClipCleanupValue
import opfic.plyst.core.ClipImageDownloader
import opfic.plyst.core.ClipImageDraftValue
import opfic.plyst.core.ClipImageOperations
import opfic.plyst.core.ClipStore
import opfic.plyst.core.ClipShareOperations
import opfic.plyst.core.ClipShareSaveValue
import opfic.plyst.core.ClipValue
import opfic.plyst.core.ClipboardCopyValue
import opfic.plyst.core.ClipboardOperations
import opfic.plyst.core.ClipboardSaveValue
import opfic.plyst.core.ClipboardUsageFailureValue
import opfic.plyst.core.ClipboardWriter
import opfic.plyst.host.model.Clip
import opfic.plyst.host.model.ClipCoreBytes
import opfic.plyst.host.model.ClipImageMetadata
import opfic.plyst.host.model.ClipSearchHistory
import opfic.plyst.host.model.ClipSearchQuery
import opfic.plyst.host.model.ClipSortOrder
import opfic.plyst.host.model.ClipUpdate
import opfic.plyst.host.model.clip
import opfic.plyst.host.model.coreValue
import opfic.plyst.host.model.epochMilliseconds
import opfic.plyst.host.model.referenceSeconds
import opfic.plyst.host.model.wellFormed

// 호출한 코루틴의 취소 상태를 코어 판정 지점에 전달
private class ClipTaskCancellation(private val job: Job) : ClipCancellationSource {
  override fun isCancelled() = job.isCancelled
}

// 데이터베이스와 이미지 루트 쌍 하나를 다루는 코어 호출 지점
// 코어 객체 소유, 실행 줄, 취소 전달, 값과 오류 변환, 원본 읽기를 담당
// 규칙, 순서, 실패, 정리, 저장 확정과 변경 알림의 순서는 코어가 결정
//
// 쌍 하나에 인스턴스 하나만 만들고 모든 호출부가 공유
// 쓰기 실패 시 기존 상태를 보존하고 ClipStorageEvent를 발행하지 않음
// 변경 사항이 없는 수정은 이벤트 발행 없이 현재 클립을 반환
// 코어 오류는 ClipStorageError나 ClipImageFileError로 변환하고 CancellationException은 그대로 전파
// 최근 검색어 연산은 ClipStorageEvent를 발행하지 않음
// 미리보기와 썸네일은 원본에서 다시 만들 수 있는 파생 파일
class ClipCoreAdapter(
  databaseFile: File,
  imagesRoot: File,
) {
  // 코어 잠금 대기가 스레드를 하나만 점유하도록 줄마다 한 줄로 실행
  // 줄을 나누어 썸네일 생성이 목록 조회를 막지 않음
  private val storageDispatcher = Dispatchers.IO.limitedParallelism(1)
  private val imageDispatcher = Dispatchers.IO.limitedParallelism(1)
  private val bufferLock = Any()
  private val reusableBuffer by lazy { ByteBuffer.allocateDirect(REUSABLE_BUFFER_CAPACITY) }
  private val subscribers = ClipStorageSubscribers()
  private val store: ClipStore
  private val images: ClipImageOperations
  private val clipboard: ClipboardOperations
  private val share: ClipShareOperations

  init {
    Log.d(TAG, "저장소 초기화 시작")
    store = coreErrors("데이터베이스 초기화", ClipStorageError.ReadFailed) { ClipStore.open(databaseFile.path, subscribers) }
    Log.i(TAG, "저장소 초기화 완료")
    if (!imagesRoot.isAbsolute || imagesRoot.path.contains('\u0000')) throw ClipImageFileError.InvalidRoot
    images =
      coreErrors("이미지 저장소 초기화", ClipImageFileError.WriteFailed) {
        ClipImageOperations.open(store, imagesRoot.canonicalPath, ClipImageCodec)
      }
    clipboard = ClipboardOperations(images)
    share = ClipShareOperations(images)
  }

  // 수집을 시작한 뒤의 모든 변경을 저장 확정 순서로 전달
  // 버퍼 용량을 제한하지 않으며 초기 스냅샷 제공과 이전 변경의 재전달은 수행하지 않음
  fun changes(): Flow<ClipStorageEvent> = subscribers.changes()

  // ClipSortOrder에서 정의한 결정적 순서로 반환
  suspend fun fetchAll(order: ClipSortOrder): List<Clip> =
    access("fetchAll", ClipStorageError.ReadFailed) {
      ClipCoreBytes.clips(store.fetchAllEncoded(order.coreValue)) ?: throw ClipStorageError.CorruptedData
    }

  // 해당 식별자가 존재하지 않으면 null을 반환
  suspend fun fetch(id: UUID): Clip? = access("fetch", ClipStorageError.ReadFailed) { store.fetch(wireID(id))?.let(::clip) }

  // 중복 식별자와 유효하지 않은 콘텐츠는 거부
  // 쓰기가 확정된 후에만 Inserted 이벤트를 발행
  suspend fun insert(clip: Clip) = access("insert", ClipStorageError.WriteFailed) { store.insert(clip.coreValue) }

  // 저장된 최신 스냅샷에 변경 사항을 적용하고 저장이 확정된 결과를 반환
  // 해당 식별자가 존재하지 않으면 NotFound를 던짐
  suspend fun update(
    id: UUID,
    change: ClipUpdate,
  ): Clip = access("update", ClipStorageError.WriteFailed) { clip(store.update(wireID(id), change.coreValue).clip) }

  // 저장값이 ClipSearchHistory 규칙을 위반하면 CorruptedData를 던짐
  suspend fun fetchSearchHistory(): ClipSearchHistory = access("fetchSearchHistory", ClipStorageError.ReadFailed) { history(store.fetchSearchTerms()) }

  // 쓰기는 읽기, ClipSearchHistory 규칙 적용, 전체 교체를 하나의 트랜잭션으로 확정
  // 규칙을 적용한 결과가 저장된 목록과 같으면 쓰지 않고 현재 목록을 반환
  suspend fun recordSearchTerm(query: ClipSearchQuery) =
    access("recordSearchTerm", ClipStorageError.WriteFailed) { history(store.recordSearchTerm(query.text.wellFormed)) }

  // 해당 검색어가 없으면 쓰지 않고 현재 기록을 반환
  suspend fun removeSearchTerm(term: String) =
    access("removeSearchTerm", ClipStorageError.WriteFailed) { history(store.removeSearchTerm(term.wellFormed)) }

  // 저장값을 해석하지 않고 모두 제거
  // CorruptedData 상태에서 복구하는 경로
  suspend fun removeAllSearchTerms() = access("removeAllSearchTerms", ClipStorageError.WriteFailed) { store.removeAllSearchTerms() }

  suspend fun saveImage(data: ByteArray): ClipImageMutationResult<Clip> {
    val draft = ClipImageDraftValue(wireID(UUID.randomUUID()), null, null, null, System.currentTimeMillis().referenceSeconds)
    val saved =
      coreCall("saveImage", imageDispatcher, ClipImageFileError.WriteFailed) { cancellation ->
        val properties = ClipImageCodec.validated(data)
        withDirectBuffer(data) { images.saveImage(it, properties, draft, cancellation) }
      }
    return ClipImageMutationResult(saved.clip.clip ?: throw ClipStorageError.CorruptedData, cleanupState(saved.cleanup))
  }

  // 공유받은 텍스트를 저장하고 공백뿐이면 null
  // 이미지 주소 판정과 내려받기와 실패 시 텍스트 저장은 코어가 결정
  // 호출마다 Dispatchers.IO에서 실행해 내려받는 동안 이미지 줄과 코어 잠금을 쥐지 않고 공유 화면끼리 기다리지 않음
  suspend fun saveSharedText(
    text: String,
    title: String?,
    downloader: ClipImageDownloader,
  ): Clip? {
    val saved =
      coreCall("saveSharedText", Dispatchers.IO, ClipStorageError.WriteFailed) {
        share.saveText(text.wellFormed, title?.wellFormed, true, downloader, it)
      }
    return (saved as? ClipShareSaveValue.Saved)?.let { clip(it.clip) }
  }

  // 클립을 재조회하지 않고 전달받은 메타데이터에 대응하는 원본을 검증
  // 같은 실행 줄에서 읽으므로 삭제와 섞이지 않음
  suspend fun loadImage(image: ClipImageMetadata): ByteArray =
    coreCall("loadImage", imageDispatcher, ClipImageFileError.ReadFailed) { File(images.loadImage(image.coreValue, it)).readBytes() }

  // 삭제와 직렬화하여 원본에서 미리보기 파일을 매번 다시 만듦
  suspend fun makePreviewFile(image: ClipImageMetadata): File =
    coreCall("makePreviewFile", imageDispatcher, ClipImageFileError.WriteFailed) { File(images.makePreview(image.coreValue, it)) }

  // 삭제와 직렬화하여 요청한 크기의 썸네일 파일을 매번 다시 만듦
  suspend fun makeThumbnailFile(
    image: ClipImageMetadata,
    maximumPixelDimension: Int,
  ): File =
    coreCall("makeThumbnailFile", imageDispatcher, ClipImageFileError.WriteFailed) {
      File(images.makeThumbnail(image.coreValue, maximumPixelDimension.toLong(), it))
    }

  // 텍스트와 이미지 클립을 모두 처리
  // 저장이 확정된 후 Deleted 이벤트를 발행
  // 해당 식별자가 존재하지 않으면 NotFound를 던짐
  // DB 삭제 확정 후 파일 정리에 실패해도 확정된 삭제를 실패로 반환하지 않음
  suspend fun delete(id: UUID): ClipImageMutationResult<UUID> {
    val cleanup = coreCall("delete", imageDispatcher, ClipStorageError.WriteFailed) { images.deleteClip(wireID(id), it) }
    return ClipImageMutationResult(id, cleanupState(cleanup))
  }

  // 구성 이후 명시적으로 호출
  // 이번에 정리하지 못한 fileID만 반환
  // DB 조회에 실패하면 후보를 변경하지 않고 오류를 던짐
  suspend fun recoverPendingCleanup(): List<UUID> =
    coreCall("recoverPendingCleanup", imageDispatcher, ClipImageFileError.DeleteFailed) { images.recoverPendingCleanup(it) }.map(UUID::fromString)

  // ClipboardService의 Mutex 안에서만 호출
  // 저장 확정 이후에는 취소를 다시 확인하지 않음
  suspend fun saveClipboardText(text: String): ClipboardSaveResult =
    saveResult(coreCall("saveClipboardText", Dispatchers.IO, ClipStorageError.WriteFailed) { clipboard.saveText(text.wellFormed, it) })

  // ClipboardService의 Mutex 안에서만 호출
  suspend fun saveClipboardImage(data: ByteArray): ClipboardSaveResult =
    try {
      val saved =
        coreCall("saveClipboardImage", Dispatchers.IO, ClipImageFileError.WriteFailed) { cancellation ->
          val properties = ClipImageCodec.validated(data)
          withDirectBuffer(data) { clipboard.saveImage(it, properties, cancellation) }
        }
      saveResult(saved)
    } catch (error: ClipImageFileError.InvalidImage) {
      ClipboardSaveResult.InvalidImage
    } catch (error: ClipImageFileError.UnsupportedImage) {
      ClipboardSaveResult.Unsupported
    }

  // ClipboardService의 Mutex 안에서만 호출
  // 쓰기 전 오류는 전파
  // 쓰기가 확인된 이후의 사용 시각 저장 실패는 부분 성공으로 반환
  suspend fun copy(
    id: UUID,
    writer: ClipboardWriter,
  ): ClipboardCopyResult {
    val copied = coreCall("copy", Dispatchers.IO, ClipImageFileError.ReadFailed) { clipboard.copy(wireID(id), writer, it) }
    return when (copied) {
      is ClipboardCopyValue.Copied -> ClipboardCopyResult.Copied(clip(copied.clip))
      is ClipboardCopyValue.WriteNotObserved -> ClipboardCopyResult.WriteNotObserved(id)
      is ClipboardCopyValue.CopiedWithoutLastUsedAt ->
        ClipboardCopyResult.CopiedWithoutLastUsedAt(clip(copied.clip), copied.copiedAt.epochMilliseconds, failure(copied.failure))
    }
  }

  // 시작 전에만 취소를 확인
  private suspend fun <T> access(
    name: String,
    fallback: ClipStorageError,
    operation: () -> T,
  ): T =
    withContext(storageDispatcher) {
      ensureActive()
      try {
        operation()
      } catch (error: Exception) {
        ClipCoreFailure.log(error, name)
        throw ClipCoreFailure.storageError(error, fallback)
      }
    }

  // UniFFI 바이트 인자는 direct buffer만 받음
  // 상한 이하 데이터는 버퍼를 재사용해 할당 비용을 줄이고 초과분은 메모리에 남지 않게 따로 할당
  private fun <T> withDirectBuffer(
    data: ByteArray,
    body: (ByteBuffer) -> T,
  ): T =
    synchronized(bufferLock) {
      val buffer = if (data.size <= REUSABLE_BUFFER_CAPACITY) reusableBuffer else ByteBuffer.allocateDirect(data.size)
      buffer.clear()
      buffer.put(data)
      buffer.flip()
      // 생성 코드는 포인터만 넘기므로 코어 호출이 끝날 때까지 버퍼 회수를 막음
      synchronized(buffer) { body(buffer) }
    }

  private fun wireID(id: UUID) = id.toString().uppercase()

  private fun history(terms: List<String>) = ClipSearchHistory.restoring(terms) ?: throw ClipStorageError.CorruptedData

  // 코어가 식별자 형식을 검사하므로 저장이 확정된 값의 변환은 실패하지 않음
  private fun clip(value: ClipValue) = value.clip ?: throw ClipStorageError.CorruptedData

  private fun cleanupState(value: ClipCleanupValue) =
    when (value) {
      is ClipCleanupValue.Completed -> ClipImageCleanupState.Completed
      is ClipCleanupValue.Pending -> ClipImageCleanupState.Pending(UUID.fromString(value.fileId))
    }

  private fun saveResult(value: ClipboardSaveValue) =
    when (value) {
      is ClipboardSaveValue.Saved -> ClipboardSaveResult.Saved(clip(value.clip))
      is ClipboardSaveValue.SavedWithPendingCleanup ->
        ClipboardSaveResult.SavedWithPendingCleanup(clip(value.clip), UUID.fromString(value.fileId))
      ClipboardSaveValue.Empty -> ClipboardSaveResult.Empty
    }

  private fun failure(value: ClipboardUsageFailureValue) =
    when (value) {
      ClipboardUsageFailureValue.Cancelled -> ClipboardUsageUpdateFailure.Cancelled
      is ClipboardUsageFailureValue.Storage ->
        (ClipCoreFailure.storageError(value.error, ClipStorageError.WriteFailed) as? ClipStorageError)
          ?.let(ClipboardUsageUpdateFailure::Storage)
          ?: ClipboardUsageUpdateFailure.Unknown
      ClipboardUsageFailureValue.Replaced -> ClipboardUsageUpdateFailure.Replaced
      ClipboardUsageFailureValue.Unknown -> ClipboardUsageUpdateFailure.Unknown
    }

  private companion object {
    const val TAG = "ClipCoreAdapter"

    // 일반적인 사진 원본이 들어가는 크기
    const val REUSABLE_BUFFER_CAPACITY = 4 * 1024 * 1024

    // 시작한 코어 호출은 끝까지 기다리고 확정된 결과를 취소로 바꾸지 않음
    // withContext의 복귀 지점이 취소로 결과를 버리므로 NonCancellable로 감쌈
    suspend fun <T> coreCall(
      name: String,
      dispatcher: CoroutineDispatcher,
      fallback: Exception,
      operation: (ClipCancellationSource) -> T,
    ): T {
      val job = currentCoroutineContext().job
      return withContext(NonCancellable) {
        withContext(dispatcher) {
          coreErrors(name, fallback) { operation(ClipTaskCancellation(job)) }
        }
      }
    }

    // 코어 오류를 어댑터 오류로 변환
    // 패닉은 호출별 대체 오류로 전달
    inline fun <T> coreErrors(
      name: String,
      fallback: Exception,
      operation: () -> T,
    ): T =
      try {
        operation()
      } catch (error: Exception) {
        ClipCoreFailure.log(error, name)
        throw ClipCoreFailure.operationError(error, fallback)
      }
  }
}
