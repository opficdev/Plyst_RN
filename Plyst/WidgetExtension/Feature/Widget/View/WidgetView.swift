//
//  WidgetView.swift
//  WidgetExtension
//
//  Created by opfic on 10/3/26.
//

import SwiftUI
import WidgetKit

struct WidgetView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "doc.on.clipboard")
                .font(.largeTitle)
            Text("클립보드 저장")
                .font(.headline)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .widgetURL(AppLink.saveClipboard.url)
        .containerBackground(.fill.tertiary, for: .widget)
    }
}
