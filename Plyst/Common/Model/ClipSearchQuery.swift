//
//  ClipSearchQuery.swift
//  Plyst
//
//  Created by opfic on 9/30/26.
//

import Foundation

/// 앞뒤 공백과 개행을 제거한 비어 있지 않은 검색어입니다.
/// 대소문자만 무시하며 발음 구별 기호와 전각/반각은 구분합니다. 정준 등가(NFC/NFD)는 Foundation의 기본 비교 규칙을 따릅니다.
struct ClipSearchQuery: Equatable, Sendable {
    let text: String

    /// 공백과 개행뿐이면 nil입니다.
    init?(_ raw: String) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        self.text = text
    }

    func matches(_ target: String) -> Bool {
        target.range(of: text, options: .caseInsensitive) != nil
    }

    /// 서로 겹치지 않는 모든 일치 범위를 target 기준 인덱스로 반환합니다. 범위는 문자(grapheme) 경계에 맞춥니다.
    func ranges(in target: String) -> [Range<String.Index>] {
        var result = [Range<String.Index>]()
        var cursor = target.startIndex
        while cursor < target.endIndex,
              let found = target.range(of: text, options: .caseInsensitive, range: cursor..<target.endIndex) {
            let composed = target.rangeOfComposedCharacterSequences(for: found)
            // 앞선 범위와 겹치지 않도록 시작점을 커서 이후로 제한합니다.
            let range = max(composed.lowerBound, cursor)..<composed.upperBound
            result.append(range)
            cursor = range.upperBound
        }
        return result
    }
}
