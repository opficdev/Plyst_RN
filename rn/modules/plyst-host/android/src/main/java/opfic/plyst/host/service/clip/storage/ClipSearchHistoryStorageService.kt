package opfic.plyst.host.service.clip.storage

import opfic.plyst.host.model.ClipSearchHistory
import opfic.plyst.host.model.ClipSearchQuery

// 최근 검색어를 클립 저장소와 같은 영구 저장소에 보관
// 쓰기는 읽기, ClipSearchHistory 규칙 적용, 전체 교체를 하나의 트랜잭션으로 확정
// 규칙을 적용한 결과가 저장된 목록과 같으면 쓰지 않고 현재 목록을 반환
// 검색어 연산은 ClipStorageEvent를 발행하지 않음
interface ClipSearchHistoryStorageService {
  // 저장값이 ClipSearchHistory 규칙을 위반하면 CorruptedData를 던짐
  suspend fun fetchSearchHistory(): ClipSearchHistory

  suspend fun recordSearchTerm(query: ClipSearchQuery): ClipSearchHistory

  // 해당 검색어가 없으면 쓰지 않고 현재 기록을 반환
  suspend fun removeSearchTerm(term: String): ClipSearchHistory

  // 저장값을 해석하지 않고 모두 제거
  // CorruptedData 상태에서 복구하는 경로
  suspend fun removeAllSearchTerms()
}
