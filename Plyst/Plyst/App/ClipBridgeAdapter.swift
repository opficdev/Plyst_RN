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
