//
//  ClipShareImportResult.swift
//  Plyst
//
//  Created by opfic on 10/2/26.
//

/// 한 번의 반입 결과입니다.
struct ClipShareImportResult: Equatable, Sendable {
    /// 이번 반입에서 본 저장소에 새로 확정된 클립 수입니다. 이미 반입되어 있던 클립은 포함하지 않습니다.
    let importedCount: Int
    /// 반입이 끝난 뒤에도 Inbox에 남아 있는 클립 수입니다. 다음 반입에서 다시 시도합니다.
    let remainingCount: Int
    /// 본 저장소에 확정된 이미지의 임시 파일 표시를 해제하지 못한 경우 true입니다. 호출부가 본 앱의 정리 복구를 다시 실행해야 합니다.
    let hasPendingCleanup: Bool

    static let empty = ClipShareImportResult(
        importedCount: 0,
        remainingCount: 0,
        hasPendingCleanup: false
    )
}
