//
//  ClipUpdate.swift
//  Plyst
//
//  Created by opfic on 9/28/26.
//

import Foundation
import PlystCore

enum ClipUpdate: Equatable, Sendable {
    /// 편집 가능한 상세 정보를 한 번에 교체
    /// nil은 대응하는 필드의 값을 제거하는 의미
    /// 새로 고정하면 요청 시각을 기록
    /// 이미 고정되어 있으면 기존 고정 시각을 유지하고 해제하면 제거
    case details(name: String?, memo: String?, isPinned: Bool, requestedAt: Date)

    var coreValue: ClipUpdateValue {
        switch self {
        case let .details(name, memo, isPinned, requestedAt):
            return .details(
                name: name,
                memo: memo,
                isPinned: isPinned,
                requestedAt: requestedAt.timeIntervalSinceReferenceDate
            )
        }
    }
}
