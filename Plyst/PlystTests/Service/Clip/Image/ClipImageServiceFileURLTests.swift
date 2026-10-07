//
//  ClipImageServiceFileURLTests.swift
//  PlystTests
//
//  Created by opfic on 10/7/26.
//

import Foundation
import XCTest
@testable import Plyst

final class ClipImageServiceFileURLTests: XCTestCase {
    private let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Plyst-image-service-\(UUID())", isDirectory: true)
    private var root: URL { directory.appendingPathComponent("images", isDirectory: true) }

    override func tearDownWithError() throws {
        try ClipImageFileSystemTestFixture.restorePermissions(at: directory)
        if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
        try super.tearDownWithError()
    }

    func testImageFileURLReturnsTheStoredOriginal() async throws {
        let data = try ClipImageTestFixture.data()
        let storage = try makeStorage()
        let service = ClipImageService(
            storage: storage,
            files: try ClipImageFileStore(rootURL: root)
        )
        let result = try await service.saveImage(data)
        let metadata = try image(in: result.value)

        let url = try await service.loadImageFileURL(metadata)

        XCTAssertTrue(url.isFileURL)
        XCTAssertEqual(try Data(contentsOf: url), data)
    }

    func testImageFileURLRejectsADeletedOriginal() async throws {
        let data = try ClipImageTestFixture.data()
        let storage = try makeStorage()
        let files = try ClipImageFileStore(rootURL: root)
        let service = ClipImageService(storage: storage, files: files)
        let result = try await service.saveImage(data)
        let metadata = try image(in: result.value)
        try files.delete(fileID: metadata.fileID)

        do {
            _ = try await service.loadImageFileURL(metadata)
            XCTFail("삭제된 원본 URL 조회 성공")
        } catch {
            XCTAssertEqual(error as? ClipImageFileError, .notFound(metadata.fileID))
        }
    }

    private func makeStorage() throws -> SQLiteClipStorageService {
        try SQLiteClipStorageService(databaseURL: directory.appendingPathComponent("clips.sqlite"))
    }

    private func image(in clip: Clip) throws -> ClipImageMetadata {
        guard case .image(let metadata) = clip.content else { throw ClipImageFileError.notImage(clip.id) }
        return metadata
    }
}
