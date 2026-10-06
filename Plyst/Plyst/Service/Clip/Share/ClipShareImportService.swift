//
//  ClipShareImportService.swift
//  Plyst
//
//  Created by opfic on 10/2/26.
//

import Foundation

/// Share Extension이 Inbox에 저장한 클립을 본 저장소로 옮깁니다.
///
/// Inbox 연결은 호출마다 열고 호출이 끝나면 닫습니다. Inbox 파일이 없거나 비어 있으면 본 저장소에 쓰지 않으므로 이벤트도 발행하지 않습니다.
/// 클립은 오래된 순서로 처리하며 본 저장소에 확정된 뒤에만 Inbox에서 제거합니다.
/// 같은 식별자가 본 저장소에 이미 있으면 이전 반입이 중단된 경우로 보고 Inbox에서만 제거합니다. 같은 클립이 두 번 추가되지 않습니다.
/// 한 클립의 복사나 제거가 실패해도 그 클립을 Inbox에 남기고 나머지를 계속 처리합니다. 남은 클립은 다음 반입에서 다시 시도합니다.
/// Inbox를 열거나 읽지 못하면 아무것도 변경하지 않고 ClipStorageError나 ClipImageFileError를 던집니다.
/// 취소하면 CancellationError를 던집니다. Inbox 제거 전에 취소된 클립은 Inbox에 남고 다음 반입에서 정리됩니다.
///
/// Inbox 이미지 폴더에서 본 앱은 읽기와 `delete(id:)`만 실행합니다. 정리 복구는 Share Extension이 실행합니다.
struct ClipShareImportService: Sendable {
    private let inboxDatabaseURL: URL
    private let inboxImagesURL: URL
    private let storage: any ClipStorageService
    private let images: ClipImageService

    init(
        inboxDatabaseURL: URL,
        inboxImagesURL: URL,
        storage: any ClipStorageService,
        images: ClipImageService
    ) {
        self.inboxDatabaseURL = inboxDatabaseURL
        self.inboxImagesURL = inboxImagesURL
        self.storage = storage
        self.images = images
    }

    func importPendingClips() async throws -> ClipShareImportResult {
        guard FileManager.default.fileExists(atPath: inboxDatabaseURL.path) else { return .empty }
        let inbox = try SQLiteClipStorageService(databaseURL: inboxDatabaseURL)
        let inboxImages = ClipImageService(
            storage: inbox,
            files: try ClipImageFileStore(rootURL: inboxImagesURL)
        )
        let clips = try await inbox.fetchAll(order: .createdAt).reversed()
        var importedCount = 0
        var remainingCount = 0
        var hasPendingCleanup = false
        for clip in clips {
            try Task.checkCancellation()
            do {
                let copied = try await copy(clip, inboxImages: inboxImages)
                if copied.isNew { importedCount += 1 }
                if copied.hasPendingCleanup { hasPendingCleanup = true }
            } catch {
                try Task.checkCancellation()
                remainingCount += 1
                continue
            }
            do {
                try await remove(clip, inbox: inbox, inboxImages: inboxImages)
            } catch ClipStorageError.notFound {
                // 이미 제거되어 있으면 목적을 달성한 상태입니다.
            } catch {
                try Task.checkCancellation()
                remainingCount += 1
            }
        }
        return ClipShareImportResult(
            importedCount: importedCount,
            remainingCount: remainingCount,
            hasPendingCleanup: hasPendingCleanup
        )
    }

    /// 클립을 본 저장소에 확정합니다. 같은 식별자가 이미 있으면 새로 추가하지 않고 isNew를 false로 반환합니다.
    private func copy(
        _ clip: Clip,
        inboxImages: ClipImageService
    ) async throws -> (isNew: Bool, hasPendingCleanup: Bool) {
        do {
            switch clip.content {
            case .text:
                try await storage.insert(clip)
                return (true, false)
            case .image(let image):
                let data = try await inboxImages.loadImage(image)
                let result = try await images.saveImage(
                    data,
                    id: clip.id,
                    name: clip.name,
                    memo: clip.memo,
                    isPinned: clip.isPinned,
                    createdAt: clip.createdAt
                )
                return (true, result.cleanup != .completed)
            }
        } catch ClipStorageError.duplicateID {
            return (false, false)
        }
    }

    /// 본 저장소에 확정된 클립을 Inbox에서 제거합니다. 이미지 파일 정리가 보류되어도 Share Extension이 다음 실행에서 복구합니다.
    private func remove(
        _ clip: Clip,
        inbox: SQLiteClipStorageService,
        inboxImages: ClipImageService
    ) async throws {
        switch clip.content {
        case .text:
            try await inbox.delete(id: clip.id)
        case .image:
            _ = try await inboxImages.delete(id: clip.id)
        }
    }
}
