//
//  ClipBridgeAdapter.swift
//  Plyst
//
//  Created by opfic on 10/7/26.
//

import Foundation
import PlystBridge

struct ClipBridgeAdapter: ClipBridgeProvider {
    let storage: any ClipStorageService
    let images: ClipImageService
    let clipboard: ClipboardService
    let photos: ClipPhotoLibraryService

    func changes() async -> AsyncStream<ClipBridgeChange> {
        let changes = await storage.changes()
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
        let clip: Clip?
        do {
            clip = try await storage.fetch(id: id)
        } catch is CancellationError {
            throw CancellationError()
        } catch ClipStorageError.corruptedData {
            throw ClipBridgeError.corruptedData
        } catch {
            throw ClipBridgeError.readFailed
        }
        guard let clip else { return nil }

        return record(from: clip)
    }

    func clips() async throws -> [ClipBridgeRecord] {
        do {
            return try await storage.fetchAll(order: .createdAt).map { record(from: $0) }
        } catch let error as CancellationError {
            throw error
        } catch ClipStorageError.corruptedData {
            throw ClipBridgeError.corruptedData
        } catch {
            throw ClipBridgeError.readFailed
        }
    }

    func updateClip(
        id: UUID,
        name: String?,
        memo: String?,
        isPinned: Bool
    ) async throws -> ClipBridgeRecord? {
        do {
            let change = ClipUpdate.details(
                name: name,
                memo: memo,
                isPinned: isPinned
            )
            let clip = try await storage.update(id: id, change: change)
            return record(from: clip)
        } catch let error as CancellationError {
            throw error
        } catch ClipStorageError.notFound {
            return nil
        } catch ClipStorageError.corruptedData {
            throw ClipBridgeError.corruptedData
        } catch {
            throw ClipBridgeError.writeFailed
        }
    }

    func deleteClip(id: UUID) async throws {
        do {
            _ = try await images.delete(id: id)
        } catch let error as CancellationError {
            throw error
        } catch ClipStorageError.notFound {
            return
        } catch ClipStorageError.corruptedData {
            throw ClipBridgeError.corruptedData
        } catch {
            throw ClipBridgeError.writeFailed
        }
    }

    func saveCurrentClipboard() async throws -> ClipBridgeClipboardSaveResult {
        do {
            switch try await clipboard.saveCurrentClipboard() {
            case .saved: return .saved
            case .savedWithPendingCleanup:
                Task { [images] in _ = try? await images.recoverPendingCleanup() }
                return .saved
            case .empty: return .empty
            case .unsupported: return .unsupported
            case .accessFailed: return .accessFailed
            case .invalidImage: return .invalidImage
            }
        } catch let error as CancellationError {
            throw error
        } catch {
            throw ClipBridgeError.saveFailed
        }
    }

    func copyClip(id: UUID) async throws -> ClipBridgeCopyResult? {
        do {
            switch try await clipboard.copy(id: id) {
            case .copied: return .copied
            case .copiedWithoutLastUsedAt: return .copiedWithoutLastUsedAt
            case .writeNotObserved: return .writeNotObserved
            }
        } catch let error as CancellationError {
            throw error
        } catch ClipStorageError.notFound {
            return nil
        } catch {
            throw ClipBridgeError.copyFailed
        }
    }

    func getClipImagePreview(id: UUID) async throws -> String? {
        do {
            guard let clip = try await storage.fetch(id: id),
                  case .image(let image) = clip.content else { return nil }
            return try await images.makePreviewFileURL(image).absoluteString
        } catch let error as CancellationError {
            throw error
        } catch {
            throw ClipBridgeError.imageUnavailable
        }
    }

    func getClipThumbnail(
        id: UUID,
        maximumPixelDimension: Int
    ) async throws -> String? {
        do {
            guard let clip = try await storage.fetch(id: id),
                  case .image(let image) = clip.content else { return nil }
            return try await images.makeThumbnailFileURL(image, maximumPixelDimension: maximumPixelDimension).absoluteString
        } catch let error as CancellationError {
            throw error
        } catch {
            throw ClipBridgeError.imageUnavailable
        }
    }

    func saveClipImageToPhotos(id: UUID) async throws -> ClipBridgePhotoSaveResult? {
        do {
            switch try await photos.save(id: id) {
            case .saved: return .saved
            case .denied: return .denied
            case .restricted: return .restricted
            }
        } catch let error as CancellationError {
            throw error
        } catch ClipStorageError.notFound {
            return nil
        } catch {
            throw ClipBridgeError.photoSaveFailed
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
            isPinned: clip.isPinned,
            isWebLink: clip.content.isWebLink,
            createdAt: clip.createdAt.timeIntervalSince1970 * 1000,
            lastUsedAt: clip.lastUsedAt.map { $0.timeIntervalSince1970 * 1000 }
        )
    }
}
