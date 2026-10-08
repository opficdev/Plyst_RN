//
//  ClipBridgeModuleImpl.swift
//  PlystBridge
//
//  Created by opfic on 10/7/26.
//

import Foundation

@objc(ClipBridgeModuleImpl)
public final class ClipBridgeModuleImpl: NSObject, Sendable {
    @MainActor private var tasks = [UUID: Task<Void, Never>]()
    @MainActor private var isInvalidated = false

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

    @objc
    public nonisolated func invalidate() {
        Task { @MainActor in
            isInvalidated = true
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
        Task { @MainActor in
            guard !isInvalidated else { return }
            let request = UUID()
            tasks[request] = Task { @MainActor in
                defer { tasks[request] = nil }
                do {
                    guard let id = UUID(uuidString: identifier) else { throw ClipBridgeError.invalidID }
                    guard let provider = ClipBridge.provider else { throw ClipBridgeError.unavailable }
                    let value = try await operation(provider, id)
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
                "uri": $0.uri,
                "contentType": $0.contentType,
                "pixelWidth": $0.pixelWidth,
                "pixelHeight": $0.pixelHeight
            ] as NSDictionary
        }
        return [
            "id": record.id,
            "text": record.text as Any? ?? NSNull(),
            "characterCount": record.text?.count ?? 0,
            "image": image as Any? ?? NSNull(),
            "name": record.name as Any? ?? NSNull(),
            "memo": record.memo as Any? ?? NSNull(),
            "isPinned": record.isPinned,
            "createdAt": record.createdAt,
            "lastUsedAt": record.lastUsedAt as Any? ?? NSNull()
        ] as NSDictionary
    }
}
