package opfic.plyst.host.model

import opfic.plyst.core.clipSearchQueryNormalized

// 앞뒤 공백과 개행을 제거한 비어 있지 않은 검색어
@JvmInline
value class ClipSearchQuery private constructor(val text: String) {
  companion object {
    // 공백과 개행뿐이면 null
    fun of(raw: String): ClipSearchQuery? = clipSearchQueryNormalized(raw.wellFormed)?.let(::ClipSearchQuery)
  }
}
