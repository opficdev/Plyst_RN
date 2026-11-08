//
//  ClipCoreAdapter.swift
//  Plyst
//
//  Created by opfic on 11/7/26.
//

import Foundation
import OSLog
import PlystCore

/// 데이터베이스와 이미지 루트 쌍 하나를 다루는 코어 호출 지점
/// 코어 객체 소유, 실행 줄, 취소 전달, 값과 오류 변환, 원본 읽기를 담당
/// 규칙, 순서, 실패, 정리, 저장 확정과 변경 알림의 순서는 코어가 결정
///
/// 쌍 하나에 인스턴스 하나만 만들고 모든 호출부가 공유
/// 저장소 줄과 이미지 줄을 나누어 썸네일 생성이 목록 조회를 막지 않음
/// 공유 텍스트 저장은 공유 줄에서 실행해 내려받기가 복구와 이미지 첨부 저장을 막지 않음
/// 별도 프로세스의 변경은 조율하지 않음
///
/// 쓰기 실패 시 기존 상태를 보존하고 ClipStorageEvent를 발행하지 않음
/// 변경 사항이 없는 수정은 이벤트 발행 없이 현재 클립을 반환
/// 코어 오류는 ClipStorageError나 ClipImageFileError로 변환하고 CancellationError는 그대로 전파
/// 최근 검색어 연산은 ClipStorageEvent를 발행하지 않음
///
/// `ShareInboxImages`는 두 프로세스가 다룸
/// 저장과 `recoverPendingCleanup`은 Share Extension만 실행
/// 본 앱은 읽기와 `delete(id:)`만 실행
/// 본 앱이 복구를 실행하면 Extension이 저장 중이라 아직 참조되지 않은 파일을 지울 수 있음
/// 같은 인스턴스가 내려받는 중인 폴더는 복구가 건너뜀
/// `<fileID>/preview`와 `<fileID>/thumbnail-<px>`는 원본에서 다시 만들 수 있는 파생 파일
/// 본 앱 이미지 루트에서만 생성하며 `ShareInboxImages`에서는 생성하지 않음
final class ClipCoreAdapter: Sendable {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "opfic.Plyst",
        category: String(describing: ClipCoreAdapter.self)
    )

    private let storageLane = ClipCoreLane(label: "opfic.Plyst.ClipCoreAdapter.storage")
    private let imageLane = ClipCoreLane(label: "opfic.Plyst.ClipCoreAdapter.image")
    private let shareLane = ClipCoreLane(label: "opfic.Plyst.ClipCoreAdapter.share")
    private let subscribers = ClipStorageSubscribers()
    private let store: ClipStore
    private let images: ClipImageOperations
    private let clipboard: ClipboardOperations
    private let share: ClipShareOperations

    init(
        databaseURL: URL,
        imagesURL: URL
    ) throws {
        Self.logger.debug("저장소 초기화 시작")
        guard databaseURL.isFileURL, !databaseURL.path.contains("\0") else {
            ClipCoreFailure.log(ClipStorageError.readFailed, operation: "저장소 경로 검사")
            throw ClipStorageError.readFailed
        }
        let store: ClipStore
        do {
            store = try ClipStore.open(path: databaseURL.path, listener: subscribers)
        } catch {
            ClipCoreFailure.log(error, operation: "데이터베이스 초기화")
            throw ClipCoreFailure.storageError(error, fallback: ClipStorageError.readFailed)
        }
        Self.logger.info("저장소 초기화 완료")
        guard imagesURL.isFileURL, !imagesURL.path.contains("\0") else { throw ClipImageFileError.invalidRoot }
        let root = imagesURL.standardizedFileURL.resolvingSymlinksInPath().path
        let images = try Self.coreCall(fallback: ClipImageFileError.writeFailed) { _ in
            try ClipImageOperations.open(store: store, root: root, codec: ClipImageCodec())
        }
        self.store = store
        self.images = images
        clipboard = ClipboardOperations(images: images)
        share = ClipShareOperations(images: images)
    }

    /// 반환 전에 독립적인 구독을 등록
    /// 각 스트림은 단일 소비자를 전제로 함
    /// 모든 활성 구독자는 이 인스턴스에서 등록 이후 발생한 모든 변경을 저장 확정 순서로 전달받음
    /// 버퍼 용량을 제한하지 않으며 초기 스냅샷 제공과 등록 이전 변경의 재전달은 수행하지 않음
    /// 구독 등록은 onTermination에서 제거되고 인스턴스가 해제되면 스트림이 종료됨
    /// 소비자는 자신의 Task를 취소하여 관찰을 종료
    /// 목록은 조회 전에 구독을 등록하고 이벤트 수신 시 다시 조회
    /// 버퍼에 남아 있는 이벤트 스냅샷을 최신 조회 결과에 덮어쓰지 않음
    func changes() -> AsyncStream<ClipStorageEvent> {
        subscribers.subscribe()
    }

    /// ClipSortOrder에서 정의한 결정적 순서로 반환
    /// 저장소가 비어 있으면 빈 배열을 반환
    func fetchAll(order: ClipSortOrder) async throws -> [Clip] {
        let clips = try await access(fallback: .readFailed) {
            guard let clips = try Clip.list(coreBytes: store.fetchAllEncoded(order: order.coreValue)) else {
                throw ClipStorageError.corruptedData
            }
            return clips
        }
        Self.logger.debug("전체 클립 조회 완료: 정렬 \(String(describing: order), privacy: .public), 결과 \(clips.count, privacy: .public)개")
        return clips
    }

    /// 해당 식별자가 존재하지 않으면 nil을 반환
    func fetch(id: Clip.ID) async throws -> Clip? {
        let clip = try await access(fallback: .readFailed) {
            try store.fetch(id: id.uuidString).map(Self.clip)
        }
        Self.logger.debug("클립 조회 완료: id \(id.uuidString, privacy: .private(mask: .hash)), 존재 \(clip != nil, privacy: .public)")
        return clip
    }

    /// 호출부에서 전달한 식별자와 시각을 사용
    /// 중복 식별자와 유효하지 않은 콘텐츠는 거부
    /// 전체 쓰기 작업의 저장이 확정된 후에만 inserted 이벤트를 발행
    func insert(_ clip: Clip) async throws {
        try await access(fallback: .writeFailed) {
            try store.insert(clip: clip.coreValue)
        }
        Self.logger.info("클립 추가 완료: id \(clip.id.uuidString, privacy: .private(mask: .hash))")
    }

    /// 저장된 최신 스냅샷에 변경 사항을 적용하고 저장이 확정된 결과를 반환
    /// 식별자, 콘텐츠, 생성 시각은 보존
    /// 해당 식별자가 존재하지 않으면 notFound 오류를 던짐
    func update(
        id: Clip.ID,
        change: ClipUpdate
    ) async throws -> Clip {
        let result = try await access(fallback: .writeFailed) {
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

    /// 저장된 순서대로 반환
    /// 비어 있으면 빈 기록을 반환
    /// 저장값이 ClipSearchHistory 규칙을 위반하면 corruptedData를 던짐
    func fetchSearchHistory() async throws -> ClipSearchHistory {
        try await access(fallback: .readFailed) {
            try Self.history(store.fetchSearchTerms())
        }
    }

    /// 검색어를 맨 앞에 기록하고 저장이 확정된 기록을 반환
    /// 쓰기는 읽기, ClipSearchHistory 규칙 적용, 전체 교체를 하나의 트랜잭션으로 확정
    /// 실패 시 기존 목록을 보존
    /// 규칙을 적용한 결과가 저장된 목록과 같으면 쓰지 않고 현재 목록을 반환
    func recordSearchTerm(_ query: ClipSearchQuery) async throws -> ClipSearchHistory {
        try await access(fallback: .writeFailed) {
            try Self.history(store.recordSearchTerm(query: query.text))
        }
    }

    /// ClipSearchHistory.remove와 같은 동등성 규칙으로 검색어를 제거하고 저장이 확정된 기록을 반환
    /// 해당 검색어가 없으면 쓰지 않고 현재 기록을 반환하며 notFound를 던지지 않음
    func removeSearchTerm(_ term: String) async throws -> ClipSearchHistory {
        try await access(fallback: .writeFailed) {
            try Self.history(store.removeSearchTerm(term: term))
        }
    }

    /// 저장값을 해석하지 않고 모두 제거
    /// corruptedData 상태에서 복구하는 경로
    func removeAllSearchTerms() async throws {
        try await access(fallback: .writeFailed) {
            try store.removeAllSearchTerms()
        }
    }

    func saveImage(
        _ data: Data,
        id: Clip.ID = UUID(),
        name: String? = nil,
        memo: String? = nil,
        pinnedAt: Date? = nil,
        createdAt: Date = Date()
    ) async throws -> ClipImageMutationResult<Clip> {
        try await imageLane.run {
            let properties = try ClipImageCodec.validated(data)
            let draft = ClipImageDraftValue(
                id: id.uuidString,
                name: name,
                memo: memo,
                pinnedAt: pinnedAt?.timeIntervalSinceReferenceDate,
                createdAt: createdAt.timeIntervalSinceReferenceDate
            )
            let saved = try Self.coreCall(fallback: ClipImageFileError.writeFailed) {
                try images.saveImage(data: data, properties: properties, draft: draft, cancellation: $0)
            }
            guard let clip = Clip(coreValue: saved.clip) else { throw ClipStorageError.corruptedData }
            return ClipImageMutationResult(value: clip, cleanup: ClipImageCleanupState(coreValue: saved.cleanup))
        }
    }

    /// 클립을 재조회하지 않고 전달받은 메타데이터에 대응하는 원본을 검증
    func loadImage(_ image: ClipImageMetadata) async throws -> Data {
        try await imageLane.run {
            let path = try Self.coreCall(fallback: ClipImageFileError.readFailed) {
                try images.loadImage(image: image.coreValue, cancellation: $0)
            }
            // 이미지 줄의 다른 작업이 끼어들 수 없으므로 삭제와 섞이지 않음
            do { return try Data(contentsOf: URL(fileURLWithPath: path)) } catch { throw ClipImageFileError.readFailed }
        }
    }

    /// 본 앱 이미지 루트에서만 호출
    /// 삭제와 직렬화하여 원본에서 미리보기 파일을 매번 다시 만듦
    func makePreviewFileURL(_ image: ClipImageMetadata) async throws -> URL {
        try await imageLane.run {
            let path = try Self.coreCall(fallback: ClipImageFileError.writeFailed) {
                try images.makePreview(image: image.coreValue, cancellation: $0)
            }
            return URL(fileURLWithPath: path)
        }
    }

    /// 본 앱 이미지 루트에서만 호출
    /// 삭제와 직렬화하여 요청한 크기의 썸네일 파일을 매번 다시 만듦
    func makeThumbnailFileURL(
        _ image: ClipImageMetadata,
        maximumPixelDimension: Int
    ) async throws -> URL {
        try await imageLane.run {
            let path = try Self.coreCall(fallback: ClipImageFileError.writeFailed) {
                try images.makeThumbnail(
                    image: image.coreValue,
                    maximumPixelDimension: Int64(maximumPixelDimension),
                    cancellation: $0
                )
            }
            return URL(fileURLWithPath: path)
        }
    }

    /// 텍스트와 이미지 클립을 모두 처리
    /// 저장이 확정된 후 deleted 이벤트를 발행
    /// 해당 식별자가 존재하지 않으면 notFound 오류를 던짐
    /// DB 삭제 확정 후 파일 정리에 실패해도 확정된 삭제를 실패로 반환하지 않음
    func delete(id: Clip.ID) async throws -> ClipImageMutationResult<Clip.ID> {
        try await imageLane.run {
            let cleanup = try Self.coreCall(fallback: ClipStorageError.writeFailed) {
                try images.deleteClip(id: id.uuidString, cancellation: $0)
            }
            return ClipImageMutationResult(value: id, cleanup: ClipImageCleanupState(coreValue: cleanup))
        }
    }

    /// 초기화 이후 명시적으로 호출
    /// 이번에 정리하지 못한 fileID만 반환
    /// DB 조회에 실패하면 후보를 변경하지 않고 오류를 반환
    func recoverPendingCleanup() async throws -> [UUID] {
        try await imageLane.run {
            try Self.coreCall(fallback: ClipImageFileError.deleteFailed) {
                try images.recoverPendingCleanup(cancellation: $0)
            }.compactMap(UUID.init(uuidString:))
        }
    }

    /// 공유받은 텍스트를 저장하고 공백뿐이면 nil
    /// 이미지 주소 판정과 내려받기와 실패 시 텍스트 저장은 코어가 결정
    /// 공유 줄에서 실행하며 내려받는 동안 이미지 줄과 코어 잠금을 쥐지 않음
    func saveSharedText(
        _ text: String,
        title: String?,
        allowsDownload: Bool,
        downloader: any ClipImageDownloader
    ) async throws -> Clip? {
        try await shareLane.run {
            let saved = try Self.coreCall(fallback: ClipStorageError.writeFailed) {
                try share.saveText(
                    text: text,
                    title: title,
                    allowsDownload: allowsDownload,
                    downloader: downloader,
                    cancellation: $0
                )
            }
            guard case .saved(let clip) = saved else { return nil }
            return try Self.clip(clip)
        }
    }

    /// 호출자의 전용 직렬 실행기에서만 호출
    /// await 없이 실행되어 호출자의 읽기와 저장 사이에 다른 호출이 끼어들지 않음
    /// 저장 확정 이후에는 취소를 다시 확인하지 않음
    func saveClipboardText(_ text: String) throws -> ClipboardSaveResult {
        let saved = try Self.coreCall(fallback: ClipStorageError.writeFailed) {
            try clipboard.saveText(text: text, cancellation: $0)
        }
        return try Self.saveResult(saved)
    }

    /// 호출자의 전용 직렬 실행기에서만 호출
    /// await 없이 실행되어 호출자의 읽기와 저장 사이에 다른 호출이 끼어들지 않음
    func saveClipboardImage(_ data: Data) throws -> ClipboardSaveResult {
        do {
            let properties = try ClipImageCodec.validated(data)
            let saved = try Self.coreCall(fallback: ClipImageFileError.writeFailed) {
                try clipboard.saveImage(data: data, properties: properties, cancellation: $0)
            }
            return try Self.saveResult(saved)
        } catch let error as ClipImageFileError {
            switch error {
            case .invalidImage:
                return .invalidImage
            case .unsupportedImage:
                return .unsupported
            default:
                throw error
            }
        }
    }

    /// 호출자의 전용 직렬 실행기에서만 호출
    /// 쓰기 전 오류는 전파
    /// 쓰기가 확인된 이후의 사용 시각 저장 실패는 부분 성공으로 반환
    func copy(
        id: Clip.ID,
        writer: any ClipboardWriter
    ) throws -> ClipboardCopyResult {
        let copied = try Self.coreCall(fallback: ClipImageFileError.readFailed) {
            try clipboard.copy(id: id.uuidString, writer: writer, cancellation: $0)
        }
        switch copied {
        case .copied(let clip):
            return .copied(try Self.clip(clip))
        case .writeNotObserved:
            return .writeNotObserved(id)
        case let .copiedWithoutLastUsedAt(clip, copiedAt, failure):
            return .copiedWithoutLastUsedAt(
                clip: try Self.clip(clip),
                copiedAt: Date(timeIntervalSinceReferenceDate: copiedAt),
                failure: ClipboardUsageUpdateFailure(coreValue: failure)
            )
        }
    }

    /// 시작 전에만 취소를 확인하고 시작한 코어 호출은 끝까지 실행
    private func access<Value: Sendable>(
        _ name: String = #function,
        fallback: ClipStorageError,
        operation: @Sendable () throws -> Value
    ) async throws -> Value {
        try await storageLane.run {
            Self.logger.debug("\(name, privacy: .public) 시작")
            do {
                try Task.checkCancellation()
                return try operation()
            } catch {
                ClipCoreFailure.log(error, operation: name)
                throw ClipCoreFailure.storageError(error, fallback: fallback)
            }
        }
    }

    private static func saveResult(_ value: ClipboardSaveValue) throws -> ClipboardSaveResult {
        switch value {
        case .saved(let clip):
            return .saved(try Self.clip(clip))
        case let .savedWithPendingCleanup(clip, fileId):
            guard let fileID = UUID(uuidString: fileId) else { throw ClipStorageError.corruptedData }
            return .savedWithPendingCleanup(try Self.clip(clip), fileID: fileID)
        case .empty:
            return .empty
        }
    }

    /// 코어가 식별자 형식을 검사하므로 저장이 확정된 값의 변환은 실패하지 않음
    private static func clip(_ value: ClipValue) throws -> Clip {
        guard let clip = Clip(coreValue: value) else { throw ClipStorageError.corruptedData }
        return clip
    }

    private static func history(_ terms: [String]) throws -> ClipSearchHistory {
        guard let history = try ClipSearchHistory(terms: terms) else {
            throw ClipStorageError.corruptedData
        }
        return history
    }

    /// 코어 작업을 호출하고 코어 오류를 어댑터 오류로 변환
    /// 패닉은 호출별 대체 오류로 전달
    private static func coreCall<Value>(
        _ name: String = #function,
        fallback: any Error,
        operation: (ClipTaskCancellation) throws -> Value
    ) throws -> Value {
        do {
            return try operation(ClipTaskCancellation())
        } catch {
            ClipCoreFailure.log(error, operation: name)
            throw ClipCoreFailure.operationError(error, fallback: fallback)
        }
    }
}
