//
//  SystemClipboardWriter.swift
//  Plyst
//
//  Created by opfic on 9/29/26.
//

import Foundation
import UIKit
import UniformTypeIdentifiers

/// 기기 간 전송 여부와 만료일을 명시적으로 구성하는 시스템 클립보드 쓰기 구현입니다.
struct SystemClipboardWriter: ClipboardWriter {
    private let localOnly: Bool
    private let expirationDate: Date?

    init(
        localOnly: Bool,
        expirationDate: Date?
    ) {
        self.localOnly = localOnly
        self.expirationDate = expirationDate
    }

    /// 호출자의 actor 밖에서 쓰기와 기록된 표현의 확인을 수행합니다.
    @concurrent
    func write(_ content: ClipboardWriteContent) async throws -> ClipboardWriteResult {
        try Task.checkCancellation()
        let pasteboard = UIPasteboard.general
        var options = [UIPasteboard.OptionsKey: Any]()
        options[.localOnly] = localOnly
        if let expirationDate { options[.expirationDate] = expirationDate }

        // setItems는 성공값을 반환하지 않으며 changeCount 갱신은 지연될 수 있어 같은 표현을 다시 읽습니다.
        // 쓰기가 시작된 이후에는 취소를 다시 확인하거나 이전 클립보드 내용을 복구하지 않습니다.
        switch content {
        case .text(let text):
            let type = UTType.utf8PlainText.identifier
            pasteboard.setItems([[type: text]], options: options)
            let written = pasteboard.value(forPasteboardType: type) as? String
            return written == text ? .observed : .notObserved
        case let .image(data, contentType):
            pasteboard.setItems([[contentType: data]], options: options)
            let written = pasteboard.data(forPasteboardType: contentType)
            return written == data ? .observed : .notObserved
        }
    }
}
