//
//  ClipSearchHistoryStorageService.swift
//  Plyst
//
//  Created by opfic on 9/30/26.
//

/// 최근 검색어를 클립 저장소와 같은 영구 저장소에 보관함
///
/// 쓰기는 읽기, ClipSearchHistory 규칙 적용, 전체 교체를 하나의 트랜잭션으로 확정함
/// 실패 시 기존 목록을 보존함
/// 규칙을 적용한 결과가 저장된 목록과 같으면 쓰지 않고 현재 목록을 반환함
/// 검색어 연산은 ClipStorageEvent를 발행하지 않음
/// 이 이벤트 인터페이스는 클립 변경에만 적용됨
/// 던지는 ClipStorageError는 readFailed, writeFailed, corruptedData로 한정하고 CancellationError는 그대로 전파함
/// 공백 검색어는 ClipSearchQuery로 표현할 수 없으므로 호출할 수 없음
protocol ClipSearchHistoryStorageService: Sendable {
    /// 저장된 순서대로 반환함
    /// 비어 있으면 빈 기록을 반환함
    /// 저장값이 ClipSearchHistory 규칙을 위반하면 corruptedData를 던짐
    func fetchSearchHistory() async throws -> ClipSearchHistory

    /// 검색어를 맨 앞에 기록하고 저장이 확정된 기록을 반환함
    func recordSearchTerm(_ query: ClipSearchQuery) async throws -> ClipSearchHistory

    /// ClipSearchHistory.remove와 같은 동등성 규칙으로 검색어를 제거하고 저장이 확정된 기록을 반환함
    /// 해당 검색어가 없으면 쓰지 않고 현재 기록을 반환하며 notFound를 던지지 않음
    func removeSearchTerm(_ term: String) async throws -> ClipSearchHistory

    /// 저장값을 해석하지 않고 모두 제거함
    /// corruptedData 상태에서 복구하는 경로
    func removeAllSearchTerms() async throws
}
