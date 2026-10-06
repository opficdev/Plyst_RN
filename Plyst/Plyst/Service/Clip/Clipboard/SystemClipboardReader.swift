//
//  SystemClipboardReader.swift
//  Plyst
//
//  Created by opfic on 9/29/26.
//

import UIKit
import UniformTypeIdentifiers

/// 호출자의 actor 밖에서 첫 항목의 형식을 확인하고 읽습니다. 변경을 감시하거나 읽기를 재시도하지 않습니다.
struct SystemClipboardReader: ClipboardReader {
    // UIPasteboard.typeListString과 typeListURL은 Swift 6에서 공유 가변 상태로 취급되어 같은 형식 목록을 값으로 둡니다.
    private static let textTypes = [UTType.utf8PlainText.identifier, UTType.plainText.identifier]
    private static let urlTypes = [UTType.url.identifier]

    @concurrent
    func read() async throws -> ClipboardReadResult {
        try Task.checkCancellation()
        let pasteboard = UIPasteboard.general
        let changeCount = pasteboard.changeCount
        let result = readFirstItem(from: pasteboard)
        try Task.checkCancellation()
        guard changeCount == pasteboard.changeCount else { return .accessFailed }
        return result
    }

    private func readFirstItem(from pasteboard: UIPasteboard) -> ClipboardReadResult {
        guard pasteboard.numberOfItems != 0 else { return .empty }
        // 첫 항목에 등록된 이미지 표현을 우선 선택하고 읽기 실패 시 텍스트나 URL로 대체하지 않습니다.
        let imageType = pasteboard.itemProviders.first?.registeredTypeIdentifiers.first {
            UTType($0)?.conforms(to: .image) == true
        }
        if let imageType {
            guard let data = pasteboard.data(forPasteboardType: imageType) else { return .accessFailed }
            return .image(data)
        }
        // hasStrings와 hasURLs는 전체 항목을 확인하므로 첫 항목의 형식만 검사합니다.
        let hasText = pasteboard.contains(pasteboardTypes: Self.textTypes)
        let hasURL = pasteboard.contains(pasteboardTypes: Self.urlTypes)
        guard hasText || hasURL else { return .unsupported }

        let text = hasText ? pasteboard.string : nil
        if let text, ClipContent.text(text).isValid { return .text(text) }
        if hasURL {
            guard let url = pasteboard.url else { return .accessFailed }
            return .text(url.absoluteString)
        }
        return text == nil ? .accessFailed : .empty
    }
}
