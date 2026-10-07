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
        Task { @MainActor in
            guard !isInvalidated else { return }
            let request = UUID()
            tasks[request] = Task { @MainActor in
                defer { tasks[request] = nil }
                do {
                    guard let id = UUID(uuidString: identifier) else { throw ClipBridgeError.invalidID }
                    guard let provider = ClipBridge.provider else { throw ClipBridgeError.unavailable }
                    let record = try await provider.clip(id: id)
                    guard !isInvalidated, !Task.isCancelled else { return }
                    completion(record.map(Self.dictionary), nil)
                } catch {
                    guard !isInvalidated, !Task.isCancelled else { return }
                    completion(nil, (error as? ClipBridgeError ?? .readFailed).code)
                }
            }
        }
    }

    @objc
    public nonisolated func invalidate() {
        Task { @MainActor in
            isInvalidated = true
            for task in tasks.values { task.cancel() }
            tasks.removeAll()
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
            "image": image as Any? ?? NSNull(),
            "name": record.name as Any? ?? NSNull(),
            "memo": record.memo as Any? ?? NSNull(),
            "isPinned": record.isPinned,
            "createdAt": record.createdAt,
            "lastUsedAt": record.lastUsedAt as Any? ?? NSNull()
        ] as NSDictionary
    }
}
