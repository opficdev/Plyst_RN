package opfic.plyst.host.service.clip.storage

import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteDatabaseCorruptException
import android.util.Log
import java.io.File
import java.util.UUID
import java.util.concurrent.CopyOnWriteArraySet
import kotlin.coroutines.cancellation.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.channels.SendChannel
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.buffer
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.withContext
import opfic.plyst.host.model.Clip
import opfic.plyst.host.model.ClipSearchHistory
import opfic.plyst.host.model.ClipSearchQuery
import opfic.plyst.host.model.ClipSortOrder
import opfic.plyst.host.model.ClipUpdate

// SQLite로 클립과 최근 검색어를 저장
// 모든 화면은 같은 인스턴스를 공유하여 클립 변경을 관찰
// 최근 검색어 연산은 ClipStorageEvent를 발행하지 않음
class SQLiteClipStorageService(databaseFile: File) : ClipStorageService, ClipSearchHistoryStorageService {
  // 쓰기 확정과 이벤트 발행 순서를 지키도록 모든 연산을 한 줄로 실행
  private val dispatcher = Dispatchers.IO.limitedParallelism(1)
  private val database: SQLiteDatabase
  private val subscriptions = CopyOnWriteArraySet<SendChannel<ClipStorageEvent>>()

  init {
    Log.d(TAG, "저장소 초기화 시작")
    val directory = databaseFile.parentFile
    if (directory == null || !(directory.isDirectory || directory.mkdirs())) {
      Log.e(TAG, "저장소 디렉터리 생성 실패")
      throw ClipStorageError.WriteFailed
    }
    database =
      try {
        SQLiteDatabase.openDatabase(
          databaseFile.path,
          null,
          SQLiteDatabase.CREATE_IF_NECESSARY or SQLiteDatabase.ENABLE_WRITE_AHEAD_LOGGING,
        )
      } catch (error: Exception) {
        Log.e(TAG, "데이터베이스 초기화 실패: ${error.javaClass.simpleName}")
        throw map(error, ClipStorageError.ReadFailed)
      }
    try {
      // WAL 기본값 NORMAL 대신 iOS 저장소와 같은 FULL 적용
      database.execSQL("PRAGMA synchronous = FULL")
      migrate()
    } catch (error: Exception) {
      Log.e(TAG, "마이그레이션 실패: ${error.javaClass.simpleName}")
      database.close()
      throw map(error, ClipStorageError.WriteFailed)
    }
    Log.i(TAG, "저장소 초기화 완료")
  }

  override suspend fun fetchAll(order: ClipSortOrder): List<Clip> =
    access(ClipStorageError.ReadFailed) {
      database.query(SQLiteClipRecord.TABLE, null, null, null, null, null, null).use { cursor ->
        val clips = mutableListOf<Clip>()
        while (cursor.moveToNext()) clips.add(SQLiteClipRecord.clip(cursor))
        order.sorted(clips)
      }
    }

  override suspend fun fetch(id: UUID): Clip? = access(ClipStorageError.ReadFailed) { find(id) }

  override suspend fun insert(clip: Clip) =
    access(ClipStorageError.WriteFailed) {
      validate(clip)
      write {
        if (find(clip.id) != null) throw ClipStorageError.DuplicateID(clip.id)
        database.insertOrThrow(SQLiteClipRecord.TABLE, null, SQLiteClipRecord.values(clip))
      }
      publish(ClipStorageEvent.Inserted(clip))
    }

  override suspend fun update(
    id: UUID,
    change: ClipUpdate,
  ): Clip =
    access(ClipStorageError.WriteFailed) {
      val (clip, changed) =
        write {
          val current = find(id) ?: throw ClipStorageError.NotFound(id)
          val updated = change.applying(current)
          if (updated == current) return@write current to false
          validate(updated)
          database.update(
            SQLiteClipRecord.TABLE,
            SQLiteClipRecord.values(updated),
            "id = ?",
            arrayOf(SQLiteClipRecord.idString(id)),
          )
          updated to true
        }
      if (changed) publish(ClipStorageEvent.Updated(clip))
      clip
    }

  override suspend fun delete(id: UUID) =
    access(ClipStorageError.WriteFailed) {
      write {
        if (find(id) == null) throw ClipStorageError.NotFound(id)
        database.delete(SQLiteClipRecord.TABLE, "id = ?", arrayOf(SQLiteClipRecord.idString(id)))
      }
      publish(ClipStorageEvent.Deleted(id))
    }

  override fun changes(): Flow<ClipStorageEvent> =
    callbackFlow {
      subscriptions.add(channel)
      awaitClose { subscriptions.remove(channel) }
    }.buffer(Channel.UNLIMITED)

  override suspend fun fetchSearchHistory(): ClipSearchHistory = access(ClipStorageError.ReadFailed) { readSearchHistory() }

  override suspend fun recordSearchTerm(query: ClipSearchQuery) = replaceSearchHistory { it.recording(query) }

  override suspend fun removeSearchTerm(term: String) = replaceSearchHistory { it.removing(term) }

  override suspend fun removeAllSearchTerms() =
    access(ClipStorageError.WriteFailed) {
      write { database.delete(SQLiteClipRecord.SEARCH_TERM_TABLE, null, null) }
      Unit
    }

  // 읽기, 규칙 적용, 전체 교체를 하나의 트랜잭션으로 처리
  // 결과가 같으면 쓰지 않음
  private suspend fun replaceSearchHistory(change: (ClipSearchHistory) -> ClipSearchHistory) =
    access(ClipStorageError.WriteFailed) {
      write {
        val current = readSearchHistory()
        val updated = change(current)
        if (updated == current) return@write current
        database.delete(SQLiteClipRecord.SEARCH_TERM_TABLE, null, null)
        updated.terms.forEachIndexed { position, term ->
          database.execSQL(
            "INSERT INTO ${SQLiteClipRecord.SEARCH_TERM_TABLE} (position, term) VALUES (?, ?)",
            arrayOf<Any>(position, term),
          )
        }
        updated
      }
    }

  private fun readSearchHistory(): ClipSearchHistory {
    val terms =
      database.query(SQLiteClipRecord.SEARCH_TERM_TABLE, arrayOf("term"), null, null, null, null, "position").use { cursor ->
        buildList { while (cursor.moveToNext()) add(cursor.getString(0)) }
      }
    return ClipSearchHistory.restoring(terms) ?: throw ClipStorageError.CorruptedData
  }

  private fun find(id: UUID): Clip? =
    database.query(SQLiteClipRecord.TABLE, null, "id = ?", arrayOf(SQLiteClipRecord.idString(id)), null, null, null).use { cursor ->
      if (cursor.moveToFirst()) SQLiteClipRecord.clip(cursor) else null
    }

  // 알려진 개수보다 많이 적용된 저장소는 이후 버전이 만든 것이라 해석하지 않음
  private fun migrate() {
    val applied = database.version
    if (SQLiteClipRecord.migrations.size < applied) throw ClipStorageError.CorruptedData
    if (applied == SQLiteClipRecord.migrations.size) return
    write {
      SQLiteClipRecord.migrations.drop(applied).forEach(database::execSQL)
      database.version = SQLiteClipRecord.migrations.size
    }
  }

  private fun <T> write(operation: () -> T): T {
    database.beginTransaction()
    try {
      val value = operation()
      database.setTransactionSuccessful()
      return value
    } finally {
      database.endTransaction()
    }
  }

  private fun publish(event: ClipStorageEvent) {
    subscriptions.forEach { it.trySend(event) }
  }

  // 쓰기가 확정될 때까지 다른 연산을 시작하지 않아 저장과 이벤트 발행 순서를 보존
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

  private fun validate(clip: Clip) {
    if (!clip.content.isValid) throw ClipStorageError.InvalidContent
  }

  private fun map(
    error: Exception,
    fallback: ClipStorageError,
  ): Exception =
    when (error) {
      is ClipStorageError -> error
      is SQLiteDatabaseCorruptException -> ClipStorageError.CorruptedData
      else -> fallback
    }

  private companion object {
    const val TAG = "SQLiteClipStorage"
  }
}
