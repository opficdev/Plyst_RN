//
//  ClipImageMutationResult.swift
//  Plyst
//
//  Created by opfic on 9/29/26.
//

import Foundation

enum ClipImageCleanupState: Equatable, Sendable {
    case completed
    /// DB 변경은 확정되었음
    /// 복구 시 현재 참조를 확인한 뒤 파일 정리를 다시 시도함
    case pending(UUID)
}

/// DB에 확정된 결과와 파일 정리 상태를 구분함
struct ClipImageMutationResult<Value: Sendable>: Sendable {
    let value: Value
    let cleanup: ClipImageCleanupState
}
