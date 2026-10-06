//
//  SearchCardText.swift
//  Plyst
//
//  Created by opfic on 9/30/26.
//

import UIKit

/// 검색 결과 카드에 표시할 강조 문자열을 만듭니다. 일치한 부분에는 배경색과 굵은 글꼴을 적용합니다.
/// 높이 계산과 표시에 같은 문자열을 쓸 수 있도록 모든 구간에 글꼴을 지정합니다.
@MainActor
enum SearchCardText {
    private static let ellipsis = "…"

    /// 이름에서 일치한 부분이 없으면 nil이며, 이때 카드는 원래 이름을 그대로 표시합니다.
    static func name(for result: SearchResult) -> NSAttributedString? {
        guard let name = result.clip.name, !result.nameRanges.isEmpty else { return nil }
        return attributed(
            text: name,
            highlights: result.nameRanges.map { NSRange($0, in: name) },
            baseFont: HomeTextCell.nameFont,
            highlightFont: .systemFont(ofSize: HomeTextCell.nameFont.pointSize, weight: .bold)
        )
    }

    /// 본문에서 일치한 부분이 없으면 nil입니다. 첫 일치가 뒤쪽에 있으면 앞을 잘라내고 `…`를 붙여 일치 부분이 보이게 합니다.
    static func body(for result: SearchResult) -> NSAttributedString? {
        guard case .text(let body) = result.clip.content, !result.bodyRanges.isEmpty else { return nil }
        let highlights = result.bodyRanges.map { NSRange($0, in: body) }
        guard let start = result.bodyExcerptStart else {
            return attributed(
                text: body,
                highlights: highlights,
                baseFont: HomeTextCell.bodyFont,
                highlightFont: .systemFont(ofSize: HomeTextCell.bodyFont.pointSize, weight: .semibold)
            )
        }
        // 잘라낸 앞부분의 길이만큼 빼고 `…`의 길이만큼 더해 범위를 옮깁니다.
        let shift = ellipsis.utf16.count - body.utf16.distance(from: body.startIndex, to: start)
        return attributed(
            text: ellipsis + String(body[start...]),
            highlights: highlights.map { NSRange(location: $0.location + shift, length: $0.length) },
            baseFont: HomeTextCell.bodyFont,
            highlightFont: .systemFont(ofSize: HomeTextCell.bodyFont.pointSize, weight: .semibold)
        )
    }

    private static func attributed(
        text: String,
        highlights: [NSRange],
        baseFont: UIFont,
        highlightFont: UIFont
    ) -> NSAttributedString {
        let result = NSMutableAttributedString(string: text, attributes: [.font: baseFont])
        for range in highlights {
            result.addAttributes(
                [
                    .font: highlightFont,
                    .backgroundColor: UIColor(resource: .searchHighlight)
                ],
                range: range
            )
        }
        return result
    }
}
