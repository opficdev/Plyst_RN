package opfic.plyst.host.model

import java.nio.ByteBuffer
import opfic.plyst.core.clipSortOrder

enum class ClipSortOrder {
  CREATED_AT;

  // 생성 시각의 내림차순으로 정렬
  // 생성 시각이 같으면 대문자 식별자 문자열의 오름차순으로 순서를 결정
  fun sorted(clips: List<Clip>): List<Clip> {
    val ids = ByteBuffer.allocate(clips.size * ID_SIZE)
    clips.forEach { ids.putLong(it.id.mostSignificantBits).putLong(it.id.leastSignificantBits) }
    return clipSortOrder(clips.map { it.createdAt.referenceSeconds }, ids.array()).map { clips[it.toInt()] }
  }

  private companion object {
    const val ID_SIZE = 16
  }
}
