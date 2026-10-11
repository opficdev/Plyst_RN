//
//  ClipSearchQuery.swift
//  Plyst
//
//  Created by opfic on 9/30/26.
//

import Foundation

/// 앞뒤 공백과 개행을 제거한 비어 있지 않은 검색어입니다.
struct ClipSearchQuery: Equatable, Sendable {
    let text: String

    /// 공백과 개행뿐이면 nil입니다.
    init?(_ raw: String) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        self.text = text
    }
}
