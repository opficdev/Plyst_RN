package opfic.plyst.host.model

import opfic.plyst.core.clipSearchHistoryRestored

// 정규화, 중복 제거, 순서, 개수 규칙을 만족하는 최근 검색어
// 첫 요소가 가장 최근
// 대소문자만 다른 검색어는 같은 항목으로 봄
data class ClipSearchHistory(val terms: List<String>) {
  companion object {
    // 저장된 목록이 규칙을 이미 만족할 때만 생성
    // 각 항목은 정규화된 형태이고 대소문자를 무시한 중복이 없으며 개수는 최대 개수 이하여야 함
    fun restoring(terms: List<String>) = clipSearchHistoryRestored(terms.map { it.wellFormed })?.let(::ClipSearchHistory)
  }
}
