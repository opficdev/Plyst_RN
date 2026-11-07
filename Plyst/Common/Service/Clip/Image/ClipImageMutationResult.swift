//
//  ClipImageMutationResult.swift
//  Plyst
//
//  Created by opfic on 9/29/26.
//

import Foundation
import PlystCore

enum ClipImageCleanupState: Equatable, Sendable {
    case completed
    /// DB 변경은 확정되었음
    /// 복구 시 현재 참조를 확인한 뒤 파일 정리를 다시 시도
    case pending(UUID)

    /// 코어가 만든 대문자 UUID라 변환은 실패하지 않음
    init(coreValue value: ClipCleanupValue) {
        switch value {
        case .completed:
            self = .completed
        case .pending(let fileId):
            self = UUID(uuidString: fileId).map(ClipImageCleanupState.pending) ?? .completed
        }
    }
}

/// DB에 확정된 결과와 파일 정리 상태를 구분
struct ClipImageMutationResult<Value: Sendable>: Sendable {
    let value: Value
    let cleanup: ClipImageCleanupState
}
