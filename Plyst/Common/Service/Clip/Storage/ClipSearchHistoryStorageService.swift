//
//  ClipSearchHistoryStorageService.swift
//  Plyst
//
//  Created by opfic on 9/30/26.
//

/// 최근 검색어를 클립 저장소와 같은 영구 저장소에 보관합니다.
///
/// 쓰기는 읽기, ClipSearchHistory 규칙 적용, 전체 교체를 하나의 트랜잭션으로 확정하며, 실패 시 기존 목록을 보존합니다.
/// 규칙을 적용한 결과가 저장된 목록과 같으면 쓰지 않고 현재 목록을 반환합니다.
/// 검색어 연산은 ClipStorageEvent를 발행하지 않습니다. 이 이벤트 계약은 클립 변경에만 적용됩니다.
/// 던지는 ClipStorageError는 readFailed, writeFailed, corruptedData로 한정하고 CancellationError는 그대로 전파합니다.
/// 공백 검색어는 ClipSearchQuery로 표현할 수 없으므로 호출할 수 없습니다.
protocol ClipSearchHistoryStorageService: Sendable {
    /// 저장된 순서대로 반환합니다. 비어 있으면 빈 기록을 반환합니다. 저장값이 ClipSearchHistory 규칙을 위반하면 corruptedData를 던집니다.
    func fetchSearchHistory() async throws -> ClipSearchHistory

    /// 검색어를 맨 앞에 기록하고 저장이 확정된 기록을 반환합니다.
    func recordSearchTerm(_ query: ClipSearchQuery) async throws -> ClipSearchHistory

    /// ClipSearchHistory.remove와 같은 동등성 규칙으로 검색어를 제거하고 저장이 확정된 기록을 반환합니다.
    /// 해당 검색어가 없으면 쓰지 않고 현재 기록을 반환하며 notFound를 던지지 않습니다.
    func removeSearchTerm(_ term: String) async throws -> ClipSearchHistory

    /// 저장값을 해석하지 않고 모두 제거합니다. corruptedData 상태에서 복구하는 경로입니다.
    func removeAllSearchTerms() async throws
}
