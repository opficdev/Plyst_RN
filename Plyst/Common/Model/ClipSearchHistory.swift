//
//  ClipSearchHistory.swift
//  Plyst
//
//  Created by opfic on 9/30/26.
//

import Foundation

/// 최근 검색어의 정규화, 중복 제거, 순서, 개수 규칙입니다. 첫 요소가 가장 최근입니다.
/// 대소문자만 다른 검색어는 같은 항목으로 봅니다.
struct ClipSearchHistory: Equatable, Sendable {
    static let maximumCount = 5

    private(set) var terms = [String]()

    init() {}

    /// 저장된 목록이 규칙을 이미 만족할 때만 생성합니다.
    /// 각 항목은 정규화된 형태여야 하고, 대소문자를 무시한 중복이 없어야 하며, 개수가 최대 개수 이하여야 합니다.
    init?(terms: [String]) {
        guard terms.count <= Self.maximumCount else { return nil }
        var restored = [String]()
        for term in terms {
            guard let query = ClipSearchQuery(term), query.text == term,
                  !restored.contains(where: { Self.isSame($0, term) }) else {
                return nil
            }
            restored.append(term)
        }
        self.terms = restored
    }

    /// 같은 항목을 제거하고 새 표기를 맨 앞에 둡니다. 최대 개수를 넘으면 가장 오래된 항목을 제거합니다.
    mutating func record(_ query: ClipSearchQuery) {
        terms.removeAll { Self.isSame($0, query.text) }
        terms.insert(query.text, at: 0)
        if Self.maximumCount < terms.count {
            terms.removeLast(terms.count - Self.maximumCount)
        }
    }

    /// 대소문자를 무시하고 같은 항목을 제거합니다. 정규화 결과가 비었거나 일치하는 항목이 없으면 변경하지 않습니다.
    mutating func remove(_ term: String) {
        guard let query = ClipSearchQuery(term) else { return }
        terms.removeAll { Self.isSame($0, query.text) }
    }

    private static func isSame(
        _ lhs: String,
        _ rhs: String
    ) -> Bool {
        lhs.compare(rhs, options: .caseInsensitive) == .orderedSame
    }
}
