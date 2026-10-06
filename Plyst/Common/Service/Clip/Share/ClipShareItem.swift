//
//  ClipShareItem.swift
//  Plyst
//
//  Created by opfic on 10/1/26.
//

import Foundation

/// 공유 시트가 전달한 첫 항목입니다.
/// NSItemProvider는 Sendable이 아니므로 MainActor에 격리하고 값은 ClipShareService가 저장을 시도할 때마다 읽습니다.
@MainActor
final class ClipShareItem {
    let providers: [NSItemProvider]
    /// 앞뒤 공백을 제거한 공유 항목 제목입니다. 공백뿐이면 nil입니다.
    nonisolated let title: String?

    init(item: NSExtensionItem?) {
        providers = item?.attachments ?? []
        let trimmed = item?.attributedTitle?.string.trimmingCharacters(in: .whitespacesAndNewlines)
        title = trimmed?.isEmpty == false ? trimmed : nil
    }
}
