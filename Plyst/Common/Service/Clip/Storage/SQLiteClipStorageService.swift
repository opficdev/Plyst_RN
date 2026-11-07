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
/// 저장 확정과 변경 알림의 순서는 ClipStore가 보장하고 이 타입은 구독자 전달만 맡음
/// 최근 검색어 연산은 ClipStorageEvent를 발행하지 않음
actor SQLiteClipStorageService: ClipStorageService {

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "opfic.Plyst",
        category: String(describing: SQLiteClipStorageService.self)
    )

    private let queue = DispatchSerialQueue(label: "opfic.Plyst.SQLiteClipStorageService")
    private let subscribers = ClipStorageSubscribers()
    let store: ClipStore

    /// 연결 잠금 대기가 협력 스레드를 막지 않도록 전용 직렬 큐에서 실행
    nonisolated var unownedExecutor: UnownedSerialExecutor { queue.asUnownedSerialExecutor() }

    init(databaseURL: URL) throws {
        Self.logger.debug("저장소 초기화 시작")
        guard databaseURL.isFileURL, !databaseURL.path.contains("\0") else {
            logClipCoreFailure(ClipStorageError.readFailed, operation: "저장소 경로 검사")
            throw ClipStorageError.readFailed
        }
        do {
            store = try ClipStore.open(path: databaseURL.path, listener: subscribers)
        } catch {
            logClipCoreFailure(error, operation: "데이터베이스 초기화")
            throw clipStorageError(error, fallback: ClipStorageError.readFailed)
        }
        Self.logger.info("저장소 초기화 완료")
    }

    deinit {
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
    }

    func update(id: Clip.ID, change: ClipUpdate) throws -> Clip {
        let result = try access(fallback: .writeFailed) {
            let result = try store.update(id: id.uuidString, change: change.coreValue)
            return (clip: try Self.clip(result.clip), changed: result.changed)
        }
        if result.changed {
            Self.logger.info("클립 수정 완료: id \(id.uuidString, privacy: .private(mask: .hash))")
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
    }

    nonisolated func changes() -> AsyncStream<ClipStorageEvent> {
        subscribers.subscribe()
    }

    /// 시작 전에만 취소를 확인하고 시작한 코어 호출은 끝까지 실행
    private func access<Value>(_ name: String = #function, fallback: ClipStorageError, operation: () throws -> Value) throws -> Value {
        Self.logger.debug("\(name, privacy: .public) 시작")
        do {
            try Task.checkCancellation()
            return try operation()
        } catch {
            logClipCoreFailure(error, operation: name)
            throw clipStorageError(error, fallback: fallback)
        }
    }

    /// 코어가 식별자 형식을 검사하므로 저장이 확정된 값의 변환은 실패하지 않음
    private static func clip(_ value: ClipValue) throws -> Clip {
        guard let clip = Clip(coreValue: value) else { throw ClipStorageError.corruptedData }
        return clip
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
