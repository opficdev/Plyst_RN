//
//  PhotoLibraryWriterSpy.swift
//  PlystTests
//
//  Created by opfic on 10/1/26.
//

import Foundation
@testable import Plyst

@MainActor
final class PhotoLibraryWriterSpy: PhotoLibraryWriter {
    struct PhotoLibraryWrite: Equatable {
        let data: Data
        let contentType: String
    }

    enum Failure: Error {
        case writeFailed
    }

    var authorization = PhotoLibraryAuthorization.authorized
    var failsWrite = false
    var cancelsAfterAuthorization = false
    var cancelsAfterWrite = false
    private(set) var authorizationCount = 0
    private(set) var writes = [PhotoLibraryWrite]()

    @MainActor
    func requestAddAuthorization() async throws -> PhotoLibraryAuthorization {
        try Task.checkCancellation()
        authorizationCount += 1
        if cancelsAfterAuthorization { withUnsafeCurrentTask { $0?.cancel() } }
        return authorization
    }

    @MainActor
    func write(
        _ data: Data,
        contentType: String
    ) async throws {
        try Task.checkCancellation()
        if failsWrite { throw Failure.writeFailed }
        writes.append(PhotoLibraryWrite(data: data, contentType: contentType))
        if cancelsAfterWrite { withUnsafeCurrentTask { $0?.cancel() } }
    }
}
