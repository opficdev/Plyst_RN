//
//  ClipboardWriterSpy.swift
//  PlystTests
//
//  Created by opfic on 9/29/26.
//

import Foundation
@testable import Plyst

@MainActor
final class ClipboardWriterSpy: ClipboardWriter {
    var result: ClipboardWriteResult
    private(set) var contents = [ClipboardWriteContent]()
    private let onWrite: () -> Void

    init(
        result: ClipboardWriteResult = .observed,
        onWrite: @escaping () -> Void = {}
    ) {
        self.result = result
        self.onWrite = onWrite
    }

    @MainActor
    func write(_ content: ClipboardWriteContent) async throws -> ClipboardWriteResult {
        try Task.checkCancellation()
        contents.append(content)
        onWrite()
        return result
    }
}
