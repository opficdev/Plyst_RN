//
//  HomeContent.swift
//  Plyst
//
//  Created by opfic on 9/30/26.
//

import Foundation

struct HomeContent: Equatable, Sendable {
    let pinnedClips: [Clip]
    let sections: [HomeSection]

    var isEmpty: Bool { pinnedClips.isEmpty && sections.isEmpty }

    /// 입력은 ClipSortOrder.createdAt 순서입니다. 전체 필터에서는 고정 항목을 상단 고정 항목으로 분리해 시간순 목록과 중복되지 않게 합니다.
    static func make(
        from clips: [Clip],
        filter: HomeFilter,
        now: Date,
        calendar: Calendar
    ) -> HomeContent {
        switch filter {
        case .all:
            let pinned = clips.filter(\.isPinned)
            let timeline = clips.filter { !$0.isPinned }
            return HomeContent(
                pinnedClips: pinned,
                sections: HomeSection.make(from: timeline, now: now, calendar: calendar)
            )
        case .text, .image, .pinned:
            let timeline = clips.filter(filter.includes)
            return HomeContent(
                pinnedClips: [],
                sections: HomeSection.make(from: timeline, now: now, calendar: calendar)
            )
        }
    }
}
