package opfic.plyst.host.model

import opfic.plyst.core.clipSearchHistoryRecording
import opfic.plyst.core.clipSearchHistoryRemoving
import opfic.plyst.core.clipSearchHistoryRestored

// 최근 검색어의 정규화, 중복 제거, 순서, 개수 규칙
// 첫 요소가 가장 최근
// 대소문자만 다른 검색어는 같은 항목으로 봄
data class ClipSearchHistory(val terms: List<String> = emptyList()) {
  // 같은 항목을 제거하고 새 표기를 맨 앞에 둠
  // 최대 개수를 넘으면 가장 오래된 항목을 제거
  fun recording(query: ClipSearchQuery) = ClipSearchHistory(clipSearchHistoryRecording(terms, query.text))

  // 대소문자를 무시하고 같은 항목을 제거
  // 정규화 결과가 비었거나 일치하는 항목이 없으면 변경하지 않음
  fun removing(term: String) = ClipSearchHistory(clipSearchHistoryRemoving(terms, term.wellFormed))

  companion object {
    // 저장된 목록이 규칙을 이미 만족할 때만 생성
    // 각 항목은 정규화된 형태이고 대소문자를 무시한 중복이 없으며 개수는 최대 개수 이하여야 함
    fun restoring(terms: List<String>) = clipSearchHistoryRestored(terms.map { it.wellFormed })?.let(::ClipSearchHistory)
  }
}
