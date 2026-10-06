//
//  WidgetProvider.swift
//  WidgetExtension
//
//  Created by opfic on 10/3/26.
//

import WidgetKit

/// 표시할 내용이 변하지 않으므로 항목 하나로 타임라인을 구성하고 다시 불러오지 않습니다.
struct WidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> WidgetEntry {
        WidgetEntry(date: .now)
    }

    func getSnapshot(
        in context: Context,
        completion: @escaping (WidgetEntry) -> Void
    ) {
        completion(WidgetEntry(date: .now))
    }

    func getTimeline(
        in context: Context,
        completion: @escaping (Timeline<WidgetEntry>) -> Void
    ) {
        completion(Timeline(entries: [WidgetEntry(date: .now)], policy: .never))
    }
}
