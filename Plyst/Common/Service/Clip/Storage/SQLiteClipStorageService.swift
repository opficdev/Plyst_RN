//
//  SQLiteClipStorageService.swift
//  Plyst
//
//  Created by opfic on 9/29/26.
//

import Foundation
import OSLog
import PlystCore

/// PlystCore의 ClipStore로 클립과 최근 검색어를 저장
/// 모든 화면은 같은 인스턴스를 공유하여 클립 변경을 관찰
/// 최근 검색어 연산은 ClipStorageEvent를 발행하지 않음
actor SQLiteClipStorageService: ClipStorageService {

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "opfic.Plyst",
        category: String(describing: SQLiteClipStorageService.self)
    )

    private let store: ClipStore
    private var subscriptions = [UUID: AsyncStream<ClipStorageEvent>.Continuation]()

    init(databaseURL: URL) throws {
        Self.logger.debug("저장소 초기화 시작")
        guard databaseURL.isFileURL, !databaseURL.path.contains("\0") else {
            Self.logFailure(ClipStorageError.readFailed, operation: "저장소 경로 검사")
            throw ClipStorageError.readFailed
        }
        do {
            try FileManager.default.createDirectory(
                at: databaseURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
        } catch {
            Self.logFailure(error, operation: "저장소 디렉터리 생성")
            throw ClipStorageError.writeFailed
        }
        do {
            store = try ClipStore.open(path: databaseURL.path)
        } catch {
            Self.logFailure(error, operation: "데이터베이스 초기화")
            throw Self.map(error, fallback: .readFailed)
        }
        Self.logger.info("저장소 초기화 완료")
    }

    deinit {
        for continuation in subscriptions.values {
            continuation.finish()
        }
        Self.logger.debug("저장소 종료")
    }

    func fetchAll(order: ClipSortOrder) throws -> [Clip] {
        let clips = try access(fallback: .readFailed) {
            guard let clips = try Clip.list(coreBytes: store.fetchAllEncoded(order: order.coreValue)) else {
                throw ClipStorageError.corruptedData
            }
            return clips
        }
        Self.logger.debug("전체 클립 조회 완료: 정렬 \(String(describing: order), privacy: .public), 결과 \(clips.count, privacy: .public)개")
        return clips
    }

    func fetch(id: Clip.ID) throws -> Clip? {
        let clip = try access(fallback: .readFailed) {
            try store.fetch(id: id.uuidString).map(Self.clip)
        }
        Self.logger.debug("클립 조회 완료: id \(id.uuidString, privacy: .private(mask: .hash)), 존재 \(clip != nil, privacy: .public)")
        return clip
    }

    func insert(_ clip: Clip) throws {
        try access(fallback: .writeFailed) {
            try store.insert(clip: clip.coreValue)
        }
        Self.logger.info("클립 추가 완료: id \(clip.id.uuidString, privacy: .private(mask: .hash))")
        publish(.inserted(clip))
    }

    func update(id: Clip.ID, change: ClipUpdate) throws -> Clip {
        let result = try access(fallback: .writeFailed) {
            let result = try store.update(id: id.uuidString, change: change.coreValue)
            return (clip: try Self.clip(result.clip), changed: result.changed)
        }
        if result.changed {
            Self.logger.info("클립 수정 완료: id \(id.uuidString, privacy: .private(mask: .hash))")
            publish(.updated(result.clip))
        } else {
            Self.logger.debug("클립 수정 생략: 변경 사항 없음, id \(id.uuidString, privacy: .private(mask: .hash))")
        }
        return result.clip
    }

    func delete(id: Clip.ID) throws {
        try access(fallback: .writeFailed) {
            try store.delete(id: id.uuidString)
        }
        Self.logger.info("클립 삭제 완료: id \(id.uuidString, privacy: .private(mask: .hash))")
        publish(.deleted(id))
    }

    func changes() -> AsyncStream<ClipStorageEvent> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<ClipStorageEvent>.makeStream(bufferingPolicy: .unbounded)
        subscriptions[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeSubscription(id) }
        }
        Self.logger.debug("변경 관찰 구독 시작: 구독자 \(self.subscriptions.count, privacy: .public)개")
        return stream
    }

    private func removeSubscription(_ id: UUID) {
        subscriptions.removeValue(forKey: id)
        Self.logger.debug("변경 관찰 구독 종료: 구독자 \(self.subscriptions.count, privacy: .public)개")
    }

    private func publish(_ event: ClipStorageEvent) {
        for continuation in subscriptions.values {
            continuation.yield(event)
        }
        Self.logger.debug("변경 이벤트 발행: 구독자 \(self.subscriptions.count, privacy: .public)개")
    }

    /// 코어 호출이 확정될 때까지 actor를 중단하지 않아 저장과 이벤트 발행 순서를 보존
    private func access<Value>(_ name: String = #function, fallback: ClipStorageError, operation: () throws -> Value) throws -> Value {
        Self.logger.debug("\(name, privacy: .public) 시작")
        do {
            try Task.checkCancellation()
            return try operation()
        } catch {
            Self.logFailure(error, operation: name)
            throw Self.map(error, fallback: fallback)
        }
    }

    /// 오류 설명에는 SQL과 저장값이 포함될 수 있어 종류와 코드만 기록
    private static func logFailure(_ error: Error, operation: String) {
        if error is CancellationError {
            logger.debug("\(operation, privacy: .public) 취소")
            return
        }
        if let error = error as? ClipStoreError {
            switch error {
            case let .ReadFailed(code, extendedCode), let .WriteFailed(code, extendedCode), let .CorruptedData(code, extendedCode):
                logger.error("\(operation, privacy: .public) 실패: SQLite 코드 \(code, privacy: .public), 확장 코드 \(extendedCode, privacy: .public)")
            case .DuplicateId:
                logger.error("\(operation, privacy: .public) 실패: duplicateID")
            case .NotFound:
                logger.error("\(operation, privacy: .public) 실패: notFound")
            case .InvalidContent:
                logger.error("\(operation, privacy: .public) 실패: invalidContent")
            }
            return
        }
        if let error = error as? ClipStorageError {
            let reason = switch error {
            case .duplicateID: "duplicateID"
            case .notFound: "notFound"
            case .invalidContent: "invalidContent"
            case .readFailed: "readFailed"
            case .writeFailed: "writeFailed"
            case .corruptedData: "corruptedData"
            }
            logger.error("\(operation, privacy: .public) 실패: \(reason, privacy: .public)")
            return
        }
        let error = error as NSError
        logger.error("\(operation, privacy: .public) 실패: 오류 영역 \(error.domain, privacy: .public), 코드 \(error.code, privacy: .public)")
    }

    /// 코어가 식별자 형식을 검사하므로 저장이 확정된 값의 변환은 실패하지 않음
    private static func clip(_ value: ClipValue) throws -> Clip {
        guard let clip = Clip(coreValue: value) else { throw ClipStorageError.corruptedData }
        return clip
    }

    private static func map(_ error: Error, fallback: ClipStorageError) -> Error {
        if error is CancellationError || error is ClipStorageError { return error }
        guard let error = error as? ClipStoreError else { return fallback }
        switch error {
        case .DuplicateId(let id):
            return UUID(uuidString: id).map(ClipStorageError.duplicateID) ?? fallback
        case .NotFound(let id):
            return UUID(uuidString: id).map(ClipStorageError.notFound) ?? fallback
        case .InvalidContent:
            return ClipStorageError.invalidContent
        case .ReadFailed:
            return ClipStorageError.readFailed
        case .WriteFailed:
            return ClipStorageError.writeFailed
        case .CorruptedData:
            return ClipStorageError.corruptedData
        }
    }
}

// store와 access 등 private 멤버를 그대로 쓰기 위해 같은 파일에 둠
extension SQLiteClipStorageService: ClipSearchHistoryStorageService {
    func fetchSearchHistory() throws -> ClipSearchHistory {
        try access(fallback: .readFailed) {
            try Self.history(store.fetchSearchTerms())
        }
    }

    func recordSearchTerm(_ query: ClipSearchQuery) throws -> ClipSearchHistory {
        try access(fallback: .writeFailed) {
            try Self.history(store.recordSearchTerm(query: query.text))
        }
    }

    func removeSearchTerm(_ term: String) throws -> ClipSearchHistory {
        try access(fallback: .writeFailed) {
            try Self.history(store.removeSearchTerm(term: term))
        }
    }

    func removeAllSearchTerms() throws {
        try access(fallback: .writeFailed) {
            try store.removeAllSearchTerms()
        }
    }

    private static func history(_ terms: [String]) throws -> ClipSearchHistory {
        guard let history = try ClipSearchHistory(terms: terms) else {
            throw ClipStorageError.corruptedData
        }
        return history
    }
}
