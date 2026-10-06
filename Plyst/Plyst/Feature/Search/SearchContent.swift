//
//  SearchContent.swift
//  Plyst
//
//  Created by opfic on 9/30/26.
//

import Foundation

/// 검색 결과 한 건입니다. 범위는 clip.name과 텍스트 본문 문자열 기준의 인덱스입니다.
struct SearchResult: Equatable, Sendable {
    let clip: Clip
    /// 이름이 없는 이미지의 대체 문구("이름 없는 이미지")는 검색 대상이 아닙니다.
    let nameRanges: [Range<String.Index>]
    let bodyRanges: [Range<String.Index>]
    /// 첫 일치가 앞쪽 40자를 넘으면 그보다 14자 앞에서 본문을 보여줍니다. nil이면 처음부터 보여줍니다.
    let bodyExcerptStart: String.Index?
}

/// 검색어와 필터를 적용한 결과입니다. 시각 표기는 HomeCardFormat.time과 같은 Calendar.current와 현재 locale을 씁니다.
/// UIKit을 import하는 HomeCardFormat과 Feature/Home의 HomeSection, HomeFilter에 의존합니다.
struct SearchContent: Equatable, Sendable {
    private static let excerptThreshold = 40
    private static let excerptLeadingOffset = 14

    static let empty = SearchContent(query: nil, results: [])

    let query: ClipSearchQuery?
    /// 입력 순서(ClipSortOrder.createdAt)를 유지합니다.
    let results: [SearchResult]

    /// 필터를 적용한 결과 기준의 개수입니다.
    var textCount: Int {
        results.count { if case .text = $0.clip.content { true } else { false } }
    }

    var imageCount: Int {
        results.count { if case .image = $0.clip.content { true } else { false } }
    }

    /// 검색어가 없으면 결과도 없습니다. 텍스트는 본문과 이름, 이미지는 이름과 저장 시각으로 찾습니다.
    static func make(
        from clips: [Clip],
        query: ClipSearchQuery?,
        filter: HomeFilter,
        now: Date
    ) -> SearchContent {
        guard let query else { return SearchContent(query: nil, results: []) }
        let results = clips.compactMap { clip -> SearchResult? in
            guard filter.includes(clip) else { return nil }
            let nameRanges = clip.name.map(query.ranges(in:)) ?? []
            switch clip.content {
            case .text(let body):
                let bodyRanges = query.ranges(in: body)
                guard !nameRanges.isEmpty || !bodyRanges.isEmpty else { return nil }
                return SearchResult(
                    clip: clip,
                    nameRanges: nameRanges,
                    bodyRanges: bodyRanges,
                    bodyExcerptStart: excerptStart(in: body, firstMatch: bodyRanges.first)
                )
            case .image:
                let matchesTime = timeTexts(for: clip, now: now).contains(where: query.matches)
                guard !nameRanges.isEmpty || matchesTime else { return nil }
                return SearchResult(
                    clip: clip,
                    nameRanges: nameRanges,
                    bodyRanges: [],
                    bodyExcerptStart: nil
                )
            }
        }
        return SearchContent(query: query, results: results)
    }

    /// 이미지 저장 시각을 찾을 때 비교하는 문자열입니다. 카드에 보이는 표기와 날짜 표기를 함께 씁니다.
    static func timeTexts(
        for clip: Clip,
        now: Date
    ) -> [String] {
        let section = HomeSection.make(from: [clip], now: now, calendar: .current).first?.kind.title ?? ""
        return [
            "\(section) \(HomeCardFormat.time(for: clip.createdAt, now: now))",
            DateFormatter.localizedString(from: clip.createdAt, dateStyle: .medium, timeStyle: .none)
        ]
    }

    private static func excerptStart(
        in body: String,
        firstMatch: Range<String.Index>?
    ) -> String.Index? {
        guard let firstMatch,
              excerptThreshold < body.distance(from: body.startIndex, to: firstMatch.lowerBound) else { return nil }
        return body.index(firstMatch.lowerBound, offsetBy: -excerptLeadingOffset)
    }
}
