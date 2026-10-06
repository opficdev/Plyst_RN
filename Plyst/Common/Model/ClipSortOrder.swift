//
//  ClipSortOrder.swift
//  Plyst
//
//  Created by opfic on 9/28/26.
//

import Foundation

enum ClipSortOrder: Equatable, Sendable {

    case createdAt
    case lastUsedAt

    /// 시각의 내림차순을 기준으로 정렬합니다. 동률인 경우 생성 시각의 내림차순과 식별자의 오름차순으로 순서를 결정합니다.
    /// lastUsedAt 기준 정렬에서는 사용 이력이 없는 클립을 사용 이력이 있는 모든 클립 뒤에 배치합니다.
    func sorted(_ clips: [Clip]) -> [Clip] {
        clips.sorted { lhs, rhs in
            if self == .lastUsedAt, lhs.lastUsedAt != rhs.lastUsedAt {
                switch (lhs.lastUsedAt, rhs.lastUsedAt) {
                case let (lhsDate?, rhsDate?):
                    return rhsDate < lhsDate
                case (nil, _):
                    return false
                case (_, nil):
                    return true
                }
            }
            if lhs.createdAt != rhs.createdAt {
                return rhs.createdAt < lhs.createdAt
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }
}
