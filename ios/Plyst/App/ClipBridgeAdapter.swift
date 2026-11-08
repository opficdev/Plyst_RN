//
//  ClipBridgeAdapter.swift
//  Plyst
//
//  Created by opfic on 10/7/26.
//

import Foundation
import PlystBridge

struct ClipBridgeAdapter: ClipBridgeProvider {
    let core: ClipCoreAdapter
    let clipboard: ClipboardService
    let photos: ClipPhotoLibraryService

    func changes() async -> AsyncStream<ClipBridgeChange> {
        let changes = core.changes()
        let (stream, continuation) = AsyncStream<ClipBridgeChange>.makeStream()
        let task = Task {
            defer { continuation.finish() }
            for await event in changes {
                guard !Task.isCancelled else { return }
                switch event {
                case .inserted(let clip):
                    continuation.yield(ClipBridgeChange(kind: .inserted, id: clip.id))
                case .updated(let clip):
                    continuation.yield(ClipBridgeChange(kind: .updated, id: clip.id))
                case .deleted(let id):
                    continuation.yield(ClipBridgeChange(kind: .deleted, id: id))
                }
            }
        }
        continuation.onTermination = { _ in task.cancel() }
        return stream
    }

    func clip(id: UUID) async throws -> ClipBridgeRecord? {
        try await bridged(fallback: .readFailed) {
            try await core.fetch(id: id).map { record(from: $0) }
        }
    }

    func clips() async throws -> [ClipBridgeRecord] {
        try await bridged(fallback: .readFailed) {
            try await core.fetchAll(order: .createdAt).map { record(from: $0) }
        }
    }

    func searchHistory() async throws -> [String] {
        try await bridged(fallback: .readFailed) {
            try await core.fetchSearchHistory().terms
        }
    }

    func recordSearchTerm(_ term: String) async throws -> [String]? {
        try await bridged(fallback: .writeFailed) {
            guard let query = try ClipSearchQuery(term) else { return nil }
            return try await core.recordSearchTerm(query).terms
        }
    }

    func removeSearchTerm(_ term: String) async throws -> [String] {
        try await bridged(fallback: .writeFailed) {
            try await core.removeSearchTerm(term).terms
        }
    }

    func removeAllSearchTerms() async throws {
        try await bridged(fallback: .writeFailed, mapsCorruption: false) {
            try await core.removeAllSearchTerms()
        }
    }

    func updateClip(
        id: UUID,
        name: String?,
        memo: String?,
        isPinned: Bool
    ) async throws -> ClipBridgeRecord? {
        try await bridged(fallback: .writeFailed) {
            do {
                let change = ClipUpdate.details(
                    name: name,
                    memo: memo,
                    isPinned: isPinned,
                    requestedAt: Date()
                )
                let clip = try await core.update(id: id, change: change)
                return record(from: clip)
            } catch ClipStorageError.notFound {
                return nil
            }
        }
    }

    func deleteClip(id: UUID) async throws {
        try await bridged(fallback: .writeFailed) {
            do {
                _ = try await core.delete(id: id)
            } catch ClipStorageError.notFound {
                return
            }
        }
    }

    func saveCurrentClipboard() async throws -> ClipBridgeClipboardSaveResult {
        try await bridged(fallback: .saveFailed, mapsCorruption: false) {
            switch try await clipboard.saveCurrentClipboard() {
            case .saved: return .saved
            case .savedWithPendingCleanup:
                Task { [core] in _ = try? await core.recoverPendingCleanup() }
                return .saved
            case .empty: return .empty
            case .unsupported: return .unsupported
            case .accessFailed: return .accessFailed
            case .invalidImage: return .invalidImage
            }
        }
    }

    func copyClip(id: UUID) async throws -> ClipBridgeCopyResult? {
        try await bridged(fallback: .copyFailed, mapsCorruption: false) {
            do {
                switch try await clipboard.copy(id: id) {
                case .copied: return .copied
                case .copiedWithoutLastUsedAt: return .copiedWithoutLastUsedAt
                case .writeNotObserved: return .writeNotObserved
                }
            } catch ClipStorageError.notFound {
                return nil
            }
        }
    }

    func getClipImagePreview(id: UUID) async throws -> String? {
        try await bridged(fallback: .imageUnavailable, mapsCorruption: false) {
            guard let clip = try await core.fetch(id: id),
                  case .image(let image) = clip.content else { return nil }
            return try await core.makePreviewFileURL(image).absoluteString
        }
    }

    func getClipThumbnail(
        id: UUID,
        maximumPixelDimension: Int
    ) async throws -> String? {
        try await bridged(fallback: .imageUnavailable, mapsCorruption: false) {
            guard let clip = try await core.fetch(id: id),
                  case .image(let image) = clip.content else { return nil }
            return try await core.makeThumbnailFileURL(image, maximumPixelDimension: maximumPixelDimension).absoluteString
        }
    }

    func saveClipImageToPhotos(id: UUID) async throws -> ClipBridgePhotoSaveResult? {
        try await bridged(fallback: .photoSaveFailed, mapsCorruption: false) {
            do {
                switch try await photos.save(id: id) {
                case .saved: return .saved
                case .denied: return .denied
                case .restricted: return .restricted
                }
            } catch ClipStorageError.notFound {
                return nil
            }
        }
    }

    /// 저장소 손상과 호출별 대체 오류를 브릿지 오류로 변환
    private func bridged<Value>(
        fallback: ClipBridgeError,
        mapsCorruption: Bool = true,
        operation: () async throws -> Value
    ) async throws -> Value {
        do {
            return try await operation()
        } catch let error as CancellationError {
            throw error
        } catch ClipStorageError.corruptedData where mapsCorruption {
            throw ClipBridgeError.corruptedData
        } catch {
            throw fallback
        }
    }

    private func record(from clip: Clip) -> ClipBridgeRecord {
        let text: String?
        let image: ClipBridgeRecord.Image?
        switch clip.content {
        case .text(let value):
            text = value
            image = nil
        case .image(let metadata):
            text = nil
            image = ClipBridgeRecord.Image(
                byteCount: metadata.byteCount,
                contentType: metadata.contentType,
                pixelWidth: metadata.pixelWidth,
                pixelHeight: metadata.pixelHeight
            )
        }
        return ClipBridgeRecord(
            id: clip.id.uuidString,
            text: text,
            image: image,
            name: clip.name,
            memo: clip.memo,
            pinnedAt: clip.pinnedAt.map { $0.timeIntervalSince1970 * 1000 },
            isWebLink: clip.content.isWebLink,
            createdAt: clip.createdAt.timeIntervalSince1970 * 1000,
            lastUsedAt: clip.lastUsedAt.map { $0.timeIntervalSince1970 * 1000 }
        )
    }
}
