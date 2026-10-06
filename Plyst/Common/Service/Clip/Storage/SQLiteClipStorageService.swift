//
//  SQLiteClipStorageService.swift
//  Plyst
//
//  Created by opfic on 9/29/26.
//

import Foundation
import OSLog
import SQLiteData

/// SQLiteData로 클립과 최근 검색어를 저장합니다. 모든 화면은 같은 인스턴스를 공유하여 클립 변경을 관찰합니다.
/// 최근 검색어 연산은 ClipStorageEvent를 발행하지 않습니다.
actor SQLiteClipStorageService: ClipStorageService {

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "opfic.Plyst",
        category: String(describing: SQLiteClipStorageService.self)
    )

    private let database: DatabaseQueue
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
        let database: DatabaseQueue
        do {
            var configuration = Configuration()
            configuration.busyMode = .timeout(5)
            configuration.journalMode = .wal
            database = try DatabaseQueue(path: databaseURL.path, configuration: configuration)
            // GRDB의 WAL 초기화가 NORMAL을 설정하므로 초기화 후 FULL을 적용합니다.
            try database.writeWithoutTransaction { connection in
                try connection.setSynchronousMode(.full)
            }
        } catch {
            Self.logFailure(error, operation: "데이터베이스 초기화")
            throw Self.map(error, fallback: .readFailed)
        }
        do {
            Self.logger.debug("마이그레이션 시작")
            try SQLiteClipRecord.migrate(database)
        } catch {
            Self.logFailure(error, operation: "마이그레이션")
            throw Self.map(error, fallback: .writeFailed)
        }
        self.database = database
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
            let clips = try database.read { connection in
                try Self.decode { try SQLiteClipRecord.fetchAll(connection).map { try $0.clip() } }
            }
            return order.sorted(clips)
        }
        Self.logger.debug("전체 클립 조회 완료: 정렬 \(String(describing: order), privacy: .public), 결과 \(clips.count, privacy: .public)개")
        return clips
    }

    func fetch(id: Clip.ID) throws -> Clip? {
        let clip = try access(fallback: .readFailed) {
            try database.read { try Self.fetch(id: id, from: $0) }
        }
        Self.logger.debug("클립 조회 완료: id \(id.uuidString, privacy: .private(mask: .hash)), 존재 \(clip != nil, privacy: .public)")
        return clip
    }

    func insert(_ clip: Clip) throws {
        try access(fallback: .writeFailed) {
            try Self.validate(clip)
            try database.write { connection in
                guard try Self.fetch(id: clip.id, from: connection) == nil else {
                    throw ClipStorageError.duplicateID(clip.id)
                }
                try SQLiteClipRecord.insert { SQLiteClipRecord(clip) }.execute(connection)
            }
        }
        Self.logger.info("클립 추가 완료: id \(clip.id.uuidString, privacy: .private(mask: .hash))")
        publish(.inserted(clip))
    }

    func update(id: Clip.ID, change: ClipUpdate) throws -> Clip {
        let result = try access(fallback: .writeFailed) {
            try database.write { connection in
                guard let current = try Self.fetch(id: id, from: connection) else {
                    throw ClipStorageError.notFound(id)
                }
                let updated = change.applying(to: current)
                guard updated != current else { return (clip: current, changed: false) }
                try Self.validate(updated)
                try SQLiteClipRecord.update(SQLiteClipRecord(updated)).execute(connection)
                return (clip: updated, changed: true)
            }
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
            try database.write { connection in
                guard try Self.fetch(id: id, from: connection) != nil else {
                    throw ClipStorageError.notFound(id)
                }
                try SQLiteClipRecord.find(id).delete().execute(connection)
            }
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

    /// write가 확정될 때까지 actor를 중단하지 않아 저장과 이벤트 발행 순서를 보존합니다.
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

    /// 오류 설명에는 SQL과 저장값이 포함될 수 있어 종류와 코드만 기록합니다.
    private static func logFailure(_ error: Error, operation: String) {
        if error is CancellationError {
            logger.debug("\(operation, privacy: .public) 취소")
            return
        }
        if let error = error as? DatabaseError {
            let resultCode = error.resultCode.rawValue
            let extendedResultCode = error.extendedResultCode.rawValue
            logger.error("\(operation, privacy: .public) 실패: SQLite 코드 \(resultCode, privacy: .public), 확장 코드 \(extendedResultCode, privacy: .public)")
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

    private static func fetch(id: Clip.ID, from connection: Database) throws -> Clip? {
        try decode { try SQLiteClipRecord.find(id).fetchOne(connection)?.clip() }
    }

    private static func decode<Value>(_ operation: () throws -> Value) throws -> Value {
        do {
            return try operation()
        } catch let error as DatabaseError {
            throw error
        } catch {
            throw ClipStorageError.corruptedData
        }
    }

    private static func validate(_ clip: Clip) throws {
        guard clip.content.isValid, clip.createdAt.timeIntervalSinceReferenceDate.isFinite,
              clip.lastUsedAt?.timeIntervalSinceReferenceDate.isFinite != false else {
            throw ClipStorageError.invalidContent
        }
    }

    private static func map(_ error: Error, fallback: ClipStorageError) -> Error {
        if error is CancellationError || error is ClipStorageError { return error }
        if let error = error as? DatabaseError,
           error.resultCode == .SQLITE_CORRUPT || error.resultCode == .SQLITE_NOTADB {
            return ClipStorageError.corruptedData
        }
        return fallback
    }
}

// database와 access 등 private 멤버를 그대로 쓰기 위해 같은 파일에 둡니다. 연결과 마이그레이션은 이 actor가 계속 소유합니다.
extension SQLiteClipStorageService: ClipSearchHistoryStorageService {
    func fetchSearchHistory() throws -> ClipSearchHistory {
        try access(fallback: .readFailed) {
            try database.read { try Self.fetchSearchHistory(from: $0) }
        }
    }

    func recordSearchTerm(_ query: ClipSearchQuery) throws -> ClipSearchHistory {
        try replaceSearchHistory(operation: "recordSearchTerm") { $0.record(query) }
    }

    func removeSearchTerm(_ term: String) throws -> ClipSearchHistory {
        try replaceSearchHistory(operation: "removeSearchTerm") { $0.remove(term) }
    }

    func removeAllSearchTerms() throws {
        try access(fallback: .writeFailed) {
            try database.write { try SQLiteClipSearchTermRecord.delete().execute($0) }
        }
    }

    /// 읽기, 규칙 적용, 전체 교체를 하나의 트랜잭션으로 처리합니다. 결과가 같으면 쓰지 않습니다.
    private func replaceSearchHistory(
        operation: String,
        change: (inout ClipSearchHistory) -> Void
    ) throws -> ClipSearchHistory {
        try access(operation, fallback: .writeFailed) {
            try database.write { connection in
                let current = try Self.fetchSearchHistory(from: connection)
                var updated = current
                change(&updated)
                guard updated != current else { return current }
                try SQLiteClipSearchTermRecord.delete().execute(connection)
                for (position, term) in updated.terms.enumerated() {
                    try SQLiteClipSearchTermRecord.insert {
                        SQLiteClipSearchTermRecord(position: position, term: term)
                    }.execute(connection)
                }
                return updated
            }
        }
    }

    private static func fetchSearchHistory(from connection: Database) throws -> ClipSearchHistory {
        let records = try SQLiteClipSearchTermRecord.order(by: \.position).fetchAll(connection)
        guard let history = ClipSearchHistory(terms: records.map(\.term)) else {
            throw ClipStorageError.corruptedData
        }
        return history
    }
}
