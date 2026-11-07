package opfic.plyst.host.service.clip.storage

import android.util.Log
import java.io.File
import java.util.UUID
import kotlin.coroutines.cancellation.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.withContext
import opfic.plyst.core.ClipStore
import opfic.plyst.core.ClipStoreException
import opfic.plyst.core.ClipValue
import opfic.plyst.host.model.Clip
import opfic.plyst.host.model.ClipSearchHistory
import opfic.plyst.host.model.ClipSearchQuery
import opfic.plyst.host.model.ClipSortOrder
import opfic.plyst.host.model.ClipUpdate
import opfic.plyst.host.model.clip
import opfic.plyst.host.model.clips
import opfic.plyst.host.model.coreValue
import opfic.plyst.host.model.wellFormed
import opfic.plyst.host.service.clip.storageError

// PlystCore의 ClipStore로 클립과 최근 검색어를 저장
// 모든 화면은 같은 인스턴스를 공유하여 클립 변경을 관찰
// 저장 확정과 변경 알림의 순서는 ClipStore가 보장하고 구독자 전달은 ClipStorageSubscribers가 맡음
// 최근 검색어 연산은 ClipStorageEvent를 발행하지 않음
class SQLiteClipStorageService(databaseFile: File) : ClipStorageService, ClipSearchHistoryStorageService {
  // 연결 잠금 대기가 스레드를 하나만 점유하도록 모든 연산을 한 줄로 실행
  private val dispatcher = Dispatchers.IO.limitedParallelism(1)
  private val subscribers = ClipStorageSubscribers()
  internal val store: ClipStore

  init {
    Log.d(TAG, "저장소 초기화 시작")
    store =
      try {
        ClipStore.open(databaseFile.path, subscribers)
      } catch (error: Exception) {
        Log.e(TAG, "데이터베이스 초기화 실패: ${error.javaClass.simpleName}")
        throw map(error, ClipStorageError.ReadFailed)
      }
    Log.i(TAG, "저장소 초기화 완료")
  }

  override suspend fun fetchAll(order: ClipSortOrder): List<Clip> =
    access(ClipStorageError.ReadFailed) {
      clips(store.fetchAllEncoded(order.coreValue)) ?: throw ClipStorageError.CorruptedData
    }

  override suspend fun fetch(id: UUID): Clip? = access(ClipStorageError.ReadFailed) { store.fetch(idString(id))?.let(::clip) }

  override suspend fun insert(clip: Clip) = access(ClipStorageError.WriteFailed) { store.insert(clip.coreValue) }

  override suspend fun update(
    id: UUID,
    change: ClipUpdate,
  ): Clip = access(ClipStorageError.WriteFailed) { clip(store.update(idString(id), change.coreValue).clip) }

  override suspend fun delete(id: UUID) = access(ClipStorageError.WriteFailed) { store.delete(idString(id)) }

  override fun changes(): Flow<ClipStorageEvent> = subscribers.changes()

  override suspend fun fetchSearchHistory(): ClipSearchHistory = access(ClipStorageError.ReadFailed) { history(store.fetchSearchTerms()) }

  override suspend fun recordSearchTerm(query: ClipSearchQuery) =
    access(ClipStorageError.WriteFailed) { history(store.recordSearchTerm(query.text.wellFormed)) }

  override suspend fun removeSearchTerm(term: String) =
    access(ClipStorageError.WriteFailed) { history(store.removeSearchTerm(term.wellFormed)) }

  override suspend fun removeAllSearchTerms() = access(ClipStorageError.WriteFailed) { store.removeAllSearchTerms() }

  private fun history(terms: List<String>) = ClipSearchHistory.restoring(terms) ?: throw ClipStorageError.CorruptedData

  // 시작 전에만 취소를 확인
  private suspend fun <T> access(
    fallback: ClipStorageError,
    operation: () -> T,
  ): T =
    withContext(dispatcher) {
      ensureActive()
      try {
        operation()
      } catch (error: CancellationException) {
        throw error
      } catch (error: Exception) {
        // 오류 설명에는 SQL과 저장값이 포함될 수 있어 종류만 기록
        Log.e(TAG, "저장소 연산 실패: ${error.javaClass.simpleName}")
        throw map(error, fallback)
      }
    }

  private fun idString(id: UUID) = id.toString().uppercase()

  // 코어가 식별자 형식을 검사하므로 저장이 확정된 값의 변환은 실패하지 않음
  private fun clip(value: ClipValue) = value.clip ?: throw ClipStorageError.CorruptedData

  private fun map(
    error: Exception,
    fallback: ClipStorageError,
  ): Exception =
    when (error) {
      is ClipStorageError -> error
      is ClipStoreException -> storageError(error, fallback)
      else -> fallback
    }

  private companion object {
    const val TAG = "SQLiteClipStorage"
  }
}
