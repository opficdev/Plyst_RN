//
//  ClipSortOrder.swift
//  Plyst
//
//  Created by opfic on 9/28/26.
//

import PlystCore

enum ClipSortOrder: Equatable, Sendable {
    /// 생성 시각의 내림차순으로 정렬
    /// 생성 시각이 같으면 식별자의 오름차순으로 순서를 결정
    case createdAt

    var coreValue: ClipSortOrderValue {
        switch self {
        case .createdAt: .createdAt
        }
    }
}
