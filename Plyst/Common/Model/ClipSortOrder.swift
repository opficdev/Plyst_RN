//
//  ClipSortOrder.swift
//  Plyst
//
//  Created by opfic on 9/28/26.
//

import Foundation

enum ClipSortOrder: Equatable, Sendable {

    case createdAt

    /// 생성 시각의 내림차순으로 정렬합니다. 생성 시각이 같으면 식별자의 오름차순으로 순서를 결정합니다.
    func sorted(_ clips: [Clip]) -> [Clip] {
        clips.sorted { lhs, rhs in
            if lhs.createdAt != rhs.createdAt {
                return rhs.createdAt < lhs.createdAt
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }
}
