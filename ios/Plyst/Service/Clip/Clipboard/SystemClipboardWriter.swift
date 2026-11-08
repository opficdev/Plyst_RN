//
//  SystemClipboardWriter.swift
//  Plyst
//
//  Created by opfic on 9/29/26.
//

import Foundation
import PlystCore
import UIKit
import UniformTypeIdentifiers

/// 기기 간 전송 여부와 만료일을 명시적으로 구성하는 시스템 클립보드 쓰기 구현
/// UIKit 객체 대신 값 타입을 받아 명시적인 요청에서만 클립보드에 씀
/// 오류는 쓰기를 시작하기 전에만 던지고 쓰기 이후에는 관찰 결과를 반환
/// observed는 쓰기 직후 첫 항목에서 요청한 표현을 확인했다는 뜻이고 notObserved는 확인하지 못했다는 뜻
/// 이후의 유지, 다른 앱의 붙여넣기, 클립보드 미변경은 보장하지 않음
final class SystemClipboardWriter: ClipboardWriter {
    private let localOnly: Bool
    private let expirationDate: Date?

    init(
        localOnly: Bool,
        expirationDate: Date?
    ) {
        self.localOnly = localOnly
        self.expirationDate = expirationDate
    }

    /// 코어의 취소 판정을 지난 호출만 들어오므로 취소를 다시 확인하지 않음
    func write(content: ClipboardWriteValue) throws -> ClipboardWriteOutcome {
        let pasteboard = UIPasteboard.general
        var options = [UIPasteboard.OptionsKey: Any]()
        options[.localOnly] = localOnly
        if let expirationDate { options[.expirationDate] = expirationDate }

        // setItems는 성공값을 반환하지 않으며 changeCount 갱신은 지연될 수 있어 같은 표현을 다시 읽음
        // 쓰기가 시작된 이후에는 취소를 다시 확인하거나 이전 클립보드 내용을 복구하지 않음
        switch content {
        case .text(let text):
            let type = UTType.utf8PlainText.identifier
            pasteboard.setItems([[type: text]], options: options)
            let written = pasteboard.value(forPasteboardType: type) as? String
            return written == text ? .observed : .notObserved
        case let .image(path, contentType):
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { throw ClipboardWriteError.ReadFailed }
            pasteboard.setItems([[contentType: data]], options: options)
            let written = pasteboard.data(forPasteboardType: contentType)
            return written == data ? .observed : .notObserved
        }
    }
}
