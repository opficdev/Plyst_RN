//
//  ClipBridgeModuleImpl.swift
//  PlystBridge
//
//  Created by opfic on 10/7/26.
//

import Foundation

@objc(ClipBridgeModuleImpl)
public final class ClipBridgeModuleImpl: NSObject, Sendable {
    private let id = UUID()
    private let emit: @Sendable (String, String) -> Void
    @MainActor private var tasks = [UUID: Task<Void, Never>]()
    @MainActor private var isInvalidated = false

    @objc
    public init(emit: @escaping @Sendable (String, String) -> Void) {
        self.emit = emit
        super.init()
    }

    @objc
    public nonisolated func ready() {
        Task { @MainActor in
            guard !isInvalidated else { return }
            ClipBridge.register(id: id, emit: emit)
        }
    }

    @objc(getClip:completion:)
    public nonisolated func getClip(
        _ identifier: String,
        completion: @escaping @Sendable (NSDictionary?, String?) -> Void
    ) {
        execute(
            identifier,
            fallback: .readFailed,
            operation: { provider, id in
                try await provider.clip(id: id)
            },
            completion: { record, code in
                completion(record.map(Self.dictionary), code)
            }
        )
    }

    @objc(getClips:)
    public nonisolated func getClips(completion: @escaping @Sendable (NSArray?, String?) -> Void) {
        execute(
            fallback: .readFailed,
            operation: {
                guard let provider = ClipBridge.provider else { throw ClipBridgeError.unavailable }
                return try await provider.clips()
            },
            completion: { records, code in
                completion(records.map { $0.map(Self.dictionary) as NSArray }, code)
            }
        )
    }

    @objc(saveCurrentClipboard:)
    public nonisolated func saveCurrentClipboard(completion: @escaping @Sendable (String?, String?) -> Void) {
        execute(
            fallback: .saveFailed,
            operation: {
                guard let provider = ClipBridge.provider else { throw ClipBridgeError.unavailable }
                return try await provider.saveCurrentClipboard()
            },
            completion: { result, code in
                completion(result?.rawValue, code)
            }
        )
    }

    @objc(updateClip:name:memo:isPinned:completion:)
    public nonisolated func updateClip(
        _ identifier: String,
        name: String?,
        memo: String?,
        isPinned: Bool,
        completion: @escaping @Sendable (NSDictionary?, String?) -> Void
    ) {
        execute(
            identifier,
            fallback: .writeFailed,
            operation: { provider, id in
                try await provider.updateClip(
                    id: id,
                    name: name,
                    memo: memo,
                    isPinned: isPinned
                )
            },
            completion: { record, code in
                completion(record.map(Self.dictionary), code)
            }
        )
    }

    @objc(deleteClip:completion:)
    public nonisolated func deleteClip(
        _ identifier: String,
        completion: @escaping @Sendable (String?) -> Void
    ) {
        execute(
            identifier,
            fallback: .writeFailed,
            operation: { provider, id in
                try await provider.deleteClip(id: id)
                return true
            },
            completion: { _, code in completion(code) }
        )
    }

    @objc(copyClip:completion:)
    public nonisolated func copyClip(
        _ identifier: String,
        completion: @escaping @Sendable (String?, String?) -> Void
    ) {
        execute(
            identifier,
            fallback: .copyFailed,
            operation: { provider, id in
                try await provider.copyClip(id: id)
            },
            completion: { result, code in
                completion(result?.rawValue, code)
            }
        )
    }

    @objc(getClipImagePreview:completion:)
    public nonisolated func getClipImagePreview(
        _ identifier: String,
        completion: @escaping @Sendable (String?, String?) -> Void
    ) {
        execute(
            identifier,
            fallback: .imageUnavailable,
            operation: { provider, id in
                try await provider.getClipImagePreview(id: id)
            },
            completion: completion
        )
    }

    @objc(getClipThumbnail:maximumPixelDimension:completion:)
    public nonisolated func getClipThumbnail(
        _ identifier: String,
        maximumPixelDimension: Double,
        completion: @escaping @Sendable (String?, String?) -> Void
    ) {
        guard let dimension = Int(exactly: maximumPixelDimension), 0 < dimension else {
            completion(nil, ClipBridgeError.imageUnavailable.code)
            return
        }
        execute(
            identifier,
            fallback: .imageUnavailable,
            operation: { provider, id in
                try await provider.getClipThumbnail(id: id, maximumPixelDimension: dimension)
            },
            completion: completion
        )
    }

    @objc(saveClipImageToPhotos:completion:)
    public nonisolated func saveClipImageToPhotos(
        _ identifier: String,
        completion: @escaping @Sendable (String?, String?) -> Void
    ) {
        execute(
            identifier,
            fallback: .photoSaveFailed,
            operation: { provider, id in
                try await provider.saveClipImageToPhotos(id: id)
            },
            completion: { result, code in
                completion(result?.rawValue, code)
            }
        )
    }

    @objc
    public nonisolated func invalidate() {
        Task { @MainActor in
            isInvalidated = true
            ClipBridge.unregister(id: id)
            for task in tasks.values { task.cancel() }
            tasks.removeAll()
        }
    }

    private nonisolated func execute<Value: Sendable>(
        _ identifier: String,
        fallback: ClipBridgeError,
        operation: @escaping @MainActor @Sendable (any ClipBridgeProvider, UUID) async throws -> Value?,
        completion: @escaping @MainActor @Sendable (Value?, String?) -> Void
    ) {
        execute(
            fallback: fallback,
            operation: {
                guard let id = UUID(uuidString: identifier) else { throw ClipBridgeError.invalidID }
                guard let provider = ClipBridge.provider else { throw ClipBridgeError.unavailable }
                return try await operation(provider, id)
            },
            completion: completion
        )
    }

    private nonisolated func execute<Value: Sendable>(
        fallback: ClipBridgeError,
        operation: @escaping @MainActor @Sendable () async throws -> Value?,
        completion: @escaping @MainActor @Sendable (Value?, String?) -> Void
    ) {
        Task { @MainActor in
            guard !isInvalidated else { return }
            let request = UUID()
            tasks[request] = Task { @MainActor in
                defer { tasks[request] = nil }
                do {
                    let value = try await operation()
                    guard !isInvalidated, !Task.isCancelled else { return }
                    completion(value, nil)
                } catch {
                    guard !isInvalidated, !Task.isCancelled else { return }
                    completion(nil, (error as? ClipBridgeError ?? fallback).code)
                }
            }
        }
    }

    private static func dictionary(_ record: ClipBridgeRecord) -> NSDictionary {
        let image = record.image.map {
            [
                "byteCountText": ByteCountFormatter.string(fromByteCount: Int64($0.byteCount), countStyle: .file),
                "contentType": $0.contentType,
                "pixelWidth": $0.pixelWidth,
                "pixelHeight": $0.pixelHeight
            ] as NSDictionary
        }
        return [
            "id": record.id,
            "text": record.text as Any? ?? NSNull(),
            "characterCount": record.text?.count ?? 0,
            "textPrefix": record.text.map { String($0.prefix(60)) } as Any? ?? NSNull(),
            "image": image as Any? ?? NSNull(),
            "name": record.name as Any? ?? NSNull(),
            "memo": record.memo as Any? ?? NSNull(),
            "isPinned": record.isPinned,
            "isWebLink": record.isWebLink,
            "createdAt": record.createdAt,
            "lastUsedAt": record.lastUsedAt as Any? ?? NSNull()
        ] as NSDictionary
    }
}
