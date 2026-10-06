//
//  PlystWidget.swift
//  WidgetExtension
//
//  Created by opfic on 10/3/26.
//

import SwiftUI
import WidgetKit

@main
struct PlystWidget: Widget {
    private static let kind = "opfic.PlystRN.Widget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: WidgetProvider()) { _ in
            WidgetView()
        }
        .configurationDisplayName("클립보드 저장")
        .description("탭하면 Plyst가 열리고 클립보드의 내용이 저장됩니다.")
        .supportedFamilies([.systemSmall])
    }
}
