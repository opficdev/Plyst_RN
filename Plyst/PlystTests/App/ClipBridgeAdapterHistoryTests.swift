//
//  ClipBridgeAdapterHistoryTests.swift
//  PlystTests
//
//  Created by opfic on 10/11/26.
//

import Foundation
import PlystBridge
import SQLiteData
import XCTest
@testable import Plyst

final class ClipBridgeAdapterHistoryTests: XCTestCase {
    private let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Plyst-bridge-history-\(UUID())", isDirectory: true)
    private var url: URL { directory.appendingPathComponent("clips.sqlite") }

    override func tearDownWithError() throws {
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
        try super.tearDownWithError()
    }

    func testHistoryReturnsEmptyList() async throws {
        let adapter = try makeAdapter()

        let terms = try await adapter.searchHistory()

        XCTAssertEqual(terms, [])
    }

    func testRecordTrimsAndKeepsFiveMostRecentTerms() async throws {
        let adapter = try makeAdapter()
        for term in ["1", "2", "3", "4", "5"] {
            _ = try await adapter.recordSearchTerm(term)
        }

        let terms = try await adapter.recordSearchTerm("  Swift \n")
        let stored = try await adapter.searchHistory()

        XCTAssertEqual(terms, ["Swift", "5", "4", "3", "2"])
        XCTAssertEqual(stored, terms)
    }

    func testRecordMovesDuplicateToFrontUsingNewSpelling() async throws {
        let adapter = try makeAdapter()
        _ = try await adapter.recordSearchTerm("qr")
        _ = try await adapter.recordSearchTerm("swift")

        let terms = try await adapter.recordSearchTerm(" QR ")
        let stored = try await adapter.searchHistory()

        XCTAssertEqual(terms, ["QR", "swift"])
        XCTAssertEqual(stored, terms)
    }

    func testBlankRecordReturnsNilWithoutAccessingHistory() async throws {
        let adapter = try makeAdapter(history: ClipSearchHistoryStorageServiceStub(failure: ClipStorageError.corruptedData))

        let terms = try await adapter.recordSearchTerm(" \n\t ")

        XCTAssertNil(terms)
    }

    func testBlankRecordPreservesStoredHistory() async throws {
        let adapter = try makeAdapter()
        _ = try await adapter.recordSearchTerm("Swift")

        let terms = try await adapter.recordSearchTerm("")
        let stored = try await adapter.searchHistory()

        XCTAssertNil(terms)
        XCTAssertEqual(stored, ["Swift"])
    }

    func testRemoveNormalizesAndIgnoresCase() async throws {
        let adapter = try makeAdapter()
        _ = try await adapter.recordSearchTerm("alpha")
        _ = try await adapter.recordSearchTerm("beta")

        let terms = try await adapter.removeSearchTerm(" ALPHA ")
        let stored = try await adapter.searchHistory()

        XCTAssertEqual(terms, ["beta"])
        XCTAssertEqual(stored, terms)
    }

    func testBlankAndMissingRemovalDoNotWrite() async throws {
        let adapter = try makeAdapter()
        _ = try await adapter.recordSearchTerm("alpha")
        let connection = try DatabaseQueue(path: url.path)
        try await connection.write {
            try $0.execute(sql: "CREATE TRIGGER rejectDelete BEFORE DELETE ON clipSearchTerms BEGIN SELECT RAISE(ABORT, 'Rejected delete'); END")
        }

        let blank = try await adapter.removeSearchTerm(" \n\t ")
        let missing = try await adapter.removeSearchTerm("missing")
        let stored = try await adapter.searchHistory()

        XCTAssertEqual(blank, ["alpha"])
        XCTAssertEqual(missing, blank)
        XCTAssertEqual(stored, blank)
    }

    func testRemoveAllPersistsEmptyHistory() async throws {
        let adapter = try makeAdapter()
        _ = try await adapter.recordSearchTerm("alpha")

        try await adapter.removeAllSearchTerms()

        let restored = try makeAdapter()
        let terms = try await restored.searchHistory()
        XCTAssertEqual(terms, [])
    }

    func testCorruptedHistoryMapsErrorsAndCanBeCleared() async throws {
        let adapter = try makeAdapter()
        let connection = try DatabaseQueue(path: url.path)
        try await connection.write {
            try $0.execute(sql: "INSERT INTO clipSearchTerms (position, term) VALUES (0, 'a'), (1, 'A')")
        }

        await assertCorrupted { _ = try await adapter.searchHistory() }
        await assertCorrupted { _ = try await adapter.recordSearchTerm("b") }
        await assertCorrupted { _ = try await adapter.removeSearchTerm("a") }
        try await adapter.removeAllSearchTerms()

        let terms = try await adapter.searchHistory()
        XCTAssertEqual(terms, [])
    }

    func testReadMapsStorageFailure() async throws {
        let adapter = try makeAdapter(history: ClipSearchHistoryStorageServiceStub(failure: ClipStorageError.readFailed))

        do {
            _ = try await adapter.searchHistory()
            XCTFail("실패해야 하는 요청이 성공했습니다.")
        } catch {
            guard case ClipBridgeError.readFailed = error else {
                return XCTFail("예상한 오류가 아닙니다: \(error)")
            }
        }
    }

    func testReadPropagatesCancellation() async throws {
        let adapter = try makeAdapter(history: ClipSearchHistoryStorageServiceStub(failure: CancellationError()))

        do {
            _ = try await adapter.searchHistory()
            XCTFail("실패해야 하는 요청이 성공했습니다.")
        } catch {
            guard error is CancellationError else {
                return XCTFail("예상한 오류가 아닙니다: \(error)")
            }
        }
    }

    func testRecordMapsStorageFailure() async throws {
        let adapter = try makeAdapter(history: ClipSearchHistoryStorageServiceStub(failure: ClipStorageError.readFailed))

        do {
            _ = try await adapter.recordSearchTerm("term")
            XCTFail("실패해야 하는 요청이 성공했습니다.")
        } catch {
            guard case ClipBridgeError.writeFailed = error else {
                return XCTFail("예상한 오류가 아닙니다: \(error)")
            }
        }
    }

    func testRecordPropagatesCancellation() async throws {
        let adapter = try makeAdapter(history: ClipSearchHistoryStorageServiceStub(failure: CancellationError()))

        do {
            _ = try await adapter.recordSearchTerm("term")
            XCTFail("실패해야 하는 요청이 성공했습니다.")
        } catch {
            guard error is CancellationError else {
                return XCTFail("예상한 오류가 아닙니다: \(error)")
            }
        }
    }

    func testRemoveMapsStorageFailure() async throws {
        let adapter = try makeAdapter(history: ClipSearchHistoryStorageServiceStub(failure: ClipStorageError.readFailed))

        do {
            _ = try await adapter.removeSearchTerm("term")
            XCTFail("실패해야 하는 요청이 성공했습니다.")
        } catch {
            guard case ClipBridgeError.writeFailed = error else {
                return XCTFail("예상한 오류가 아닙니다: \(error)")
            }
        }
    }

    func testRemovePropagatesCancellation() async throws {
        let adapter = try makeAdapter(history: ClipSearchHistoryStorageServiceStub(failure: CancellationError()))

        do {
            _ = try await adapter.removeSearchTerm("term")
            XCTFail("실패해야 하는 요청이 성공했습니다.")
        } catch {
            guard error is CancellationError else {
                return XCTFail("예상한 오류가 아닙니다: \(error)")
            }
        }
    }

    func testRemoveAllMapsStorageFailure() async throws {
        let adapter = try makeAdapter(history: ClipSearchHistoryStorageServiceStub(failure: ClipStorageError.readFailed))

        do {
            try await adapter.removeAllSearchTerms()
            XCTFail("실패해야 하는 요청이 성공했습니다.")
        } catch {
            guard case ClipBridgeError.writeFailed = error else {
                return XCTFail("예상한 오류가 아닙니다: \(error)")
            }
        }
    }

    func testRemoveAllPropagatesCancellation() async throws {
        let adapter = try makeAdapter(history: ClipSearchHistoryStorageServiceStub(failure: CancellationError()))

        do {
            try await adapter.removeAllSearchTerms()
            XCTFail("실패해야 하는 요청이 성공했습니다.")
        } catch {
            guard error is CancellationError else {
                return XCTFail("예상한 오류가 아닙니다: \(error)")
            }
        }
    }

    private func assertCorrupted(_ operation: () async throws -> Void) async {
        do {
            try await operation()
            XCTFail("손상된 기록을 정상으로 처리했습니다.")
        } catch {
            guard case ClipBridgeError.corruptedData = error else {
                return XCTFail("예상한 오류가 아닙니다: \(error)")
            }
        }
    }

    private func makeAdapter(history: (any ClipSearchHistoryStorageService)? = nil) throws -> ClipBridgeAdapter {
        let storage = try SQLiteClipStorageService(databaseURL: url)
        let files = try ClipImageFileStore(rootURL: directory.appendingPathComponent("images"))
        let images = ClipImageService(storage: storage, files: files)
        return ClipBridgeAdapter(
            storage: storage,
            history: history ?? storage,
            images: images,
            clipboard: ClipboardService(storage: storage, images: images),
            photos: ClipPhotoLibraryService(storage: storage, images: images)
        )
    }
}

private struct ClipSearchHistoryStorageServiceStub: ClipSearchHistoryStorageService {
    let failure: any Error

    func fetchSearchHistory() async throws -> ClipSearchHistory { throw failure }
    func recordSearchTerm(_ query: ClipSearchQuery) async throws -> ClipSearchHistory { throw failure }
    func removeSearchTerm(_ term: String) async throws -> ClipSearchHistory { throw failure }
    func removeAllSearchTerms() async throws { throw failure }
}
