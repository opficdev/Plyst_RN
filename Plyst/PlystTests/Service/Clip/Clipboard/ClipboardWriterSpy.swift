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
    private(set) var contents = [ClipboardWriteContent]()

    @MainActor
    func write(_ content: ClipboardWriteContent) async throws -> ClipboardWriteResult {
        try Task.checkCancellation()
        contents.append(content)
        return .observed
    }
}
