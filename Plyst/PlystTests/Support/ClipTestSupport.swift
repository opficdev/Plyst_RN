//
//  ClipTestSupport.swift
//  PlystTests
//
//  Created by opfic on 11/4/26.
//

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import Plyst

/// 임시 폴더를 쓰는 테스트의 공용 기반
class ClipTemporaryDirectoryTestCase: XCTestCase {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Plyst-\(UUID())", isDirectory: true)
    var url: URL { directory.appendingPathComponent("clips.sqlite") }
    var root: URL { directory.appendingPathComponent("images", isDirectory: true) }

    override func tearDownWithError() throws {
        try ClipImageFileSystemTestFixture.restorePermissions(at: directory)
        if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
        try super.tearDownWithError()
    }

    func makeStorage() throws -> SQLiteClipStorageService {
        try SQLiteClipStorageService(databaseURL: url)
    }

    func makeAdapter(storage: any ClipStorageService) throws -> ClipBridgeAdapter {
        let images = ClipImageService(storage: storage, files: try ClipImageFileStore(rootURL: root))
        return ClipBridgeAdapter(
            storage: storage,
            history: try makeStorage(),
            images: images,
            clipboard: ClipboardService(storage: storage, images: images),
            photos: ClipPhotoLibraryService(storage: storage, images: images)
        )
    }

    func imageMetadata(in clip: Clip) throws -> ClipImageMetadata {
        guard case .image(let image) = clip.content else { throw ClipImageFileError.notImage(clip.id) }
        return image
    }

    /// 이미지 루트 아래의 항목 수
    /// 저장된 이미지 하나당 디렉터리 하나가 있음
    func entryCount(at url: URL) throws -> Int {
        try FileManager.default.contentsOfDirectory(atPath: url.path).count
    }
}

extension XCTestCase {
    /// 스트림의 이벤트가 기대한 순서로 도착하는지 검사
    func assertEvents(
        _ stream: AsyncStream<ClipStorageEvent>,
        expected: [ClipStorageEvent]
    ) async {
        let received = expectation(description: "확정된 저장 변경만 이벤트로 전달")
        let task = Task {
            var iterator = stream.makeAsyncIterator()
            for event in expected {
                let actual = await iterator.next()
                XCTAssertEqual(actual, event)
            }
            received.fulfill()
        }
        await fulfillment(of: [received], timeout: 2)
        task.cancel()
        await task.value
    }
}

/// 실제 저장소 호출 앞에 거부와 동작을 끼워 넣는 대역
actor ClipStorageServiceSpy: ClipStorageService {
    enum Operation: Hashable { case delete, list }
    private let storage: SQLiteClipStorageService
    private var rejected = Set<Operation>()
    private var yieldsBeforeInsert = false
    private let beforeInsert: @Sendable (Clip) throws -> Void
    private let beforeUpdate: @Sendable () async throws -> Void
    private let beforeDelete: @Sendable (Clip.ID) throws -> Void

    init(
        storage: SQLiteClipStorageService,
        beforeInsert: @escaping @Sendable (Clip) throws -> Void = { _ in },
        beforeUpdate: @escaping @Sendable () async throws -> Void = {},
        beforeDelete: @escaping @Sendable (Clip.ID) throws -> Void = { _ in }
    ) {
        self.storage = storage
        self.beforeInsert = beforeInsert
        self.beforeUpdate = beforeUpdate
        self.beforeDelete = beforeDelete
    }

    func reject(_ operation: Operation) { rejected.insert(operation) }
    func allow(_ operation: Operation) { rejected.remove(operation) }
    func yieldBeforeInsert() { yieldsBeforeInsert = true }

    func fetchAll(order: ClipSortOrder) async throws -> [Clip] {
        if rejected.contains(.list) { throw ClipStorageError.readFailed }
        return try await storage.fetchAll(order: order)
    }

    func fetch(id: Clip.ID) async throws -> Clip? { try await storage.fetch(id: id) }

    func insert(_ clip: Clip) async throws {
        try beforeInsert(clip)
        if yieldsBeforeInsert { await Task.yield() }
        try await storage.insert(clip)
    }

    func update(
        id: Clip.ID,
        change: ClipUpdate
    ) async throws -> Clip {
        try await beforeUpdate()
        return try await storage.update(id: id, change: change)
    }

    func delete(id: Clip.ID) async throws {
        try beforeDelete(id)
        if rejected.contains(.delete) { throw ClipStorageError.writeFailed }
        try await storage.delete(id: id)
    }

    func changes() async -> AsyncStream<ClipStorageEvent> { await storage.changes() }
}

@MainActor
final class ClipboardReaderSpy: ClipboardReader {
    private let result: ClipboardReadResult
    private(set) var readCount = 0

    init(result: ClipboardReadResult) {
        self.result = result
    }

    @MainActor
    func read() async throws -> ClipboardReadResult {
        readCount += 1
        return result
    }
}

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

enum ClipImageTestFixture {
    static func data(
        type: String = UTType.png.identifier,
        count: Int = 1,
        orientation: Int = 1
    ) throws -> Data {
        let pixels = Data(repeating: 255, count: 24)
        let provider = try XCTUnwrap(CGDataProvider(data: pixels as CFData))
        let image = try XCTUnwrap(CGImage(
            width: 2,
            height: 3,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: 8,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ))
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data as CFMutableData, type as CFString, count, nil))
        for _ in 0..<count {
            CGImageDestinationAddImage(destination, image, [kCGImagePropertyOrientation: orientation] as CFDictionary)
        }
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }
}

enum ClipImageFileSystemTestFixture {
    static func makeReadOnly(_ directory: URL) throws {
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)
        if FileManager.default.isWritableFile(atPath: directory.path) {
            throw XCTSkip("디렉터리 쓰기 권한 제한을 적용할 수 없는 실행 환경")
        }
    }

    static func restorePermissions(at root: URL) throws {
        guard FileManager.default.fileExists(atPath: root.path) else { return }
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
        let entries = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        while let entry = entries?.nextObject() as? URL {
            let properties = try entry.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            if properties.isDirectory == true, properties.isSymbolicLink != true {
                try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: entry.path)
            }
        }
    }
}
