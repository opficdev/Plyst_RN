package opfic.plyst.host.service.clip.storage

import android.content.ContentValues
import android.database.Cursor
import java.util.UUID
import kotlin.math.roundToLong
import opfic.plyst.host.model.Clip
import opfic.plyst.host.model.ClipContent
import opfic.plyst.host.model.ClipImageMetadata

// 영구 저장 필드와 도메인 값의 변환
// 날짜는 iOS 저장소와 같이 2001-01-01 기준 초를 저장
internal object SQLiteClipRecord {
  const val TABLE = "clips"
  const val SEARCH_TERM_TABLE = "clipSearchTerms"

  // clips.sqlite의 모든 스키마 마이그레이션을 순서대로 등록
  // user_version이 적용한 개수이며 새 마이그레이션은 이 목록 끝에 추가
  val migrations =
    listOf(
      // CreateClips
      """
      CREATE TABLE clips (
        id TEXT PRIMARY KEY NOT NULL,
        kind TEXT NOT NULL CHECK (kind = 'text' OR kind = 'image'),
        text TEXT,
        imageFileID TEXT,
        imageContentType TEXT,
        pixelWidth INTEGER,
        pixelHeight INTEGER,
        byteCount INTEGER,
        name TEXT,
        pinnedAt REAL,
        memo TEXT,
        createdAt REAL NOT NULL,
        lastUsedAt REAL,
        CHECK (
          (kind = 'text' AND text IS NOT NULL
            AND imageFileID IS NULL AND imageContentType IS NULL
            AND pixelWidth IS NULL AND pixelHeight IS NULL AND byteCount IS NULL)
          OR (kind = 'image' AND text IS NULL
            AND imageFileID IS NOT NULL AND imageContentType IS NOT NULL
            AND pixelWidth IS NOT NULL AND 0 < pixelWidth
            AND pixelHeight IS NOT NULL AND 0 < pixelHeight
            AND byteCount IS NOT NULL AND 0 < byteCount)
        )
      )
      """,
      // CreateClipSearchTerms
      """
      CREATE TABLE clipSearchTerms (
        position INTEGER PRIMARY KEY NOT NULL CHECK (0 <= position),
        term TEXT NOT NULL UNIQUE CHECK (term != '')
      )
      """,
    )

  // 1970-01-01부터 2001-01-01까지의 초
  private const val REFERENCE_DATE_OFFSET = 978_307_200.0

  fun values(clip: Clip) =
    ContentValues().apply {
      put("id", idString(clip.id))
      when (val content = clip.content) {
        is ClipContent.Text -> {
          put("kind", "text")
          put("text", content.text)
          putNull("imageFileID")
          putNull("imageContentType")
          putNull("pixelWidth")
          putNull("pixelHeight")
          putNull("byteCount")
        }
        is ClipContent.Image -> {
          put("kind", "image")
          putNull("text")
          put("imageFileID", idString(content.image.fileID))
          put("imageContentType", content.image.contentType)
          put("pixelWidth", content.image.pixelWidth)
          put("pixelHeight", content.image.pixelHeight)
          put("byteCount", content.image.byteCount)
        }
      }
      put("name", clip.name)
      putDate("pinnedAt", clip.pinnedAt)
      put("memo", clip.memo)
      putDate("createdAt", clip.createdAt)
      putDate("lastUsedAt", clip.lastUsedAt)
    }

  // 저장값이 도메인 규칙과 맞지 않으면 CorruptedData를 던짐
  fun clip(cursor: Cursor): Clip {
    val text = cursor.string("text")
    val imageFileID = cursor.string("imageFileID")
    val imageContentType = cursor.string("imageContentType")
    val pixelWidth = cursor.int("pixelWidth")
    val pixelHeight = cursor.int("pixelHeight")
    val byteCount = cursor.int("byteCount")
    val content =
      when (cursor.string("kind")) {
        "text" -> {
          if (text == null || imageFileID != null || imageContentType != null ||
            pixelWidth != null || pixelHeight != null || byteCount != null
          ) {
            throw ClipStorageError.CorruptedData
          }
          ClipContent.Text(text)
        }
        "image" -> {
          if (text != null || imageFileID == null || imageContentType == null ||
            pixelWidth == null || pixelHeight == null || byteCount == null
          ) {
            throw ClipStorageError.CorruptedData
          }
          ClipContent.Image(
            ClipImageMetadata(
              fileID = uuid(imageFileID),
              contentType = imageContentType,
              pixelWidth = pixelWidth,
              pixelHeight = pixelHeight,
              byteCount = byteCount,
            ),
          )
        }
        else -> throw ClipStorageError.CorruptedData
      }
    if (!content.isValid) throw ClipStorageError.CorruptedData
    return Clip(
      id = uuid(cursor.string("id") ?: throw ClipStorageError.CorruptedData),
      content = content,
      name = cursor.string("name"),
      pinnedAt = cursor.date("pinnedAt"),
      memo = cursor.string("memo"),
      createdAt = cursor.date("createdAt") ?: throw ClipStorageError.CorruptedData,
      lastUsedAt = cursor.date("lastUsedAt"),
    )
  }

  fun idString(id: UUID) = id.toString().uppercase()

  private fun uuid(value: String) =
    runCatching { UUID.fromString(value) }.getOrNull()?.takeIf { idString(it) == value }
      ?: throw ClipStorageError.CorruptedData

  private fun ContentValues.putDate(
    key: String,
    milliseconds: Long?,
  ) {
    if (milliseconds == null) putNull(key) else put(key, milliseconds / 1000.0 - REFERENCE_DATE_OFFSET)
  }

  private fun Cursor.string(column: String): String? {
    val index = getColumnIndexOrThrow(column)
    return if (isNull(index)) null else getString(index)
  }

  private fun Cursor.int(column: String): Int? {
    val index = getColumnIndexOrThrow(column)
    return if (isNull(index)) null else getInt(index)
  }

  private fun Cursor.date(column: String): Long? {
    val index = getColumnIndexOrThrow(column)
    if (isNull(index)) return null
    val seconds = getDouble(index)
    if (!seconds.isFinite()) throw ClipStorageError.CorruptedData
    return ((seconds + REFERENCE_DATE_OFFSET) * 1000).roundToLong()
  }
}
