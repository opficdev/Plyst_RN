//
//  HomeSection.swift
//  Plyst
//
//  Created by opfic on 9/30/26.
//

import Foundation

struct HomeSection: Equatable, Sendable {
    enum Kind: Int, CaseIterable, Sendable {
        case recent
        case today
        case yesterday
        case earlier

        var title: String {
            switch self {
            case .recent: "방금"
            case .today: "오늘"
            case .yesterday: "어제"
            case .earlier: "이전"
            }
        }
    }

    let kind: Kind
    let clips: [Clip]

    /// 입력은 ClipSortOrder.createdAt 순서입니다. 자정이 지나도 최근 5분을 먼저 방금으로 분류합니다.
    static func make(
        from clips: [Clip],
        now: Date,
        calendar: Calendar
    ) -> [HomeSection] {
        let recentStart = now.addingTimeInterval(-5 * 60)
        let todayStart = calendar.startOfDay(for: now)
        let yesterdayStart = calendar.date(byAdding: .day, value: -1, to: todayStart) ?? todayStart
        var groups = [Kind: [Clip]]()

        for clip in clips {
            let kind: Kind
            if recentStart < clip.createdAt {
                kind = .recent
            } else if todayStart <= clip.createdAt {
                kind = .today
            } else if yesterdayStart <= clip.createdAt {
                kind = .yesterday
            } else {
                kind = .earlier
            }
            groups[kind, default: []].append(clip)
        }

        return Kind.allCases.compactMap { kind in
            guard let clips = groups[kind], !clips.isEmpty else { return nil }
            return HomeSection(kind: kind, clips: clips)
        }
    }
}
