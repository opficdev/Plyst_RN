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

    func changes() async -> AsyncStream<ClipBridgeChange> {
        let changes = await storage.changes()
        let (stream, continuation) = AsyncStream<ClipBridgeChange>.makeStream()
        let task = Task {
            defer { continuation.finish() }
            for await event in changes {
                guard !Task.isCancelled else { return }
                switch event {
                case .inserted:
                    continue
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

        return try await record(from: clip)
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
            return try await record(from: clip)
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

    private func record(from clip: Clip) async throws -> ClipBridgeRecord {
        let text: String?
        let image: ClipBridgeRecord.Image?
        switch clip.content {
        case .text(let value):
            text = value
            image = nil
        case .image(let metadata):
            text = nil
            do {
                let url = try await images.loadImageFileURL(metadata)
                image = ClipBridgeRecord.Image(
                    uri: url.absoluteString,
                    contentType: metadata.contentType,
                    pixelWidth: metadata.pixelWidth,
                    pixelHeight: metadata.pixelHeight
                )
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                throw ClipBridgeError.imageUnavailable
            }
        }
        return ClipBridgeRecord(
            id: clip.id.uuidString,
            text: text,
            image: image,
            name: clip.name,
            memo: clip.memo,
            isPinned: clip.isPinned,
            createdAt: clip.createdAt.timeIntervalSince1970 * 1000,
            lastUsedAt: clip.lastUsedAt.map { $0.timeIntervalSince1970 * 1000 }
        )
    }
}
