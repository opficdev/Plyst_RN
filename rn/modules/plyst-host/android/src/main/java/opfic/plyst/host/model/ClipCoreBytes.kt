package opfic.plyst.host.model

import java.nio.BufferUnderflowException
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.UUID

private const val IMAGE = 1
private const val NAME = 1 shl 1
private const val PINNED_AT = 1 shl 2
private const val MEMO = 1 shl 3
private const val LAST_USED_AT = 1 shl 4

// ClipStore.fetchAllEncoded 버퍼의 해석
// 형식은 core/src/store/wire.rs가 소유
// 버퍼가 형식과 맞지 않으면 null
internal fun clips(coreBytes: ByteArray): List<Clip>? {
  val buffer = ByteBuffer.wrap(coreBytes).order(ByteOrder.LITTLE_ENDIAN)
  val clips = ArrayList<Clip>()
  try {
    while (buffer.hasRemaining()) clips.add(buffer.clip())
  } catch (_: BufferUnderflowException) {
    return null
  } catch (_: IllegalArgumentException) {
    return null
  } catch (_: IndexOutOfBoundsException) {
    return null
  }
  return clips
}

private fun ByteBuffer.clip(): Clip {
  val id = uuid()
  val flags = get().toInt()
  val createdAt = double.epochMilliseconds
  val content = if (flags and IMAGE != 0) image() else ClipContent.Text(string())
  val name = if (flags and NAME != 0) string() else null
  val pinnedAt = if (flags and PINNED_AT != 0) double.epochMilliseconds else null
  val memo = if (flags and MEMO != 0) string() else null
  val lastUsedAt = if (flags and LAST_USED_AT != 0) double.epochMilliseconds else null
  return Clip(id, content, name, pinnedAt, memo, createdAt, lastUsedAt)
}

private fun ByteBuffer.image(): ClipContent.Image {
  val fileID = uuid()
  val pixelWidth = long.toInt()
  val pixelHeight = long.toInt()
  val byteCount = long.toInt()
  return ClipContent.Image(ClipImageMetadata(fileID, string(), pixelWidth, pixelHeight, byteCount))
}

// 식별자 바이트는 UUID 표기 순서
private fun ByteBuffer.uuid() = UUID(java.lang.Long.reverseBytes(long), java.lang.Long.reverseBytes(long))

private fun ByteBuffer.string(): String {
  val count = int
  val text = String(array(), arrayOffset() + position(), count, Charsets.UTF_8)
  position(position() + count)
  return text
}
