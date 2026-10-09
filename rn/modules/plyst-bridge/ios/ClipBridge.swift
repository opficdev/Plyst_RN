//
//  ClipBridge.swift
//  PlystBridge
//
//  Created by opfic on 10/7/26.
//

import Foundation

public struct ClipBridgeRecord: Sendable {
    public struct Image: Sendable {
        public let uri: String
        public let contentType: String
        public let pixelWidth: Int
        public let pixelHeight: Int

        public init(
            uri: String,
            contentType: String,
            pixelWidth: Int,
            pixelHeight: Int
        ) {
            self.uri = uri
            self.contentType = contentType
            self.pixelWidth = pixelWidth
            self.pixelHeight = pixelHeight
        }
    }

    public let id: String
    public let text: String?
    public let image: Image?
    public let name: String?
    public let memo: String?
    public let isPinned: Bool
    public let createdAt: Double
    public let lastUsedAt: Double?

    public init(
        id: String,
        text: String?,
        image: Image?,
        name: String?,
        memo: String?,
        isPinned: Bool,
        createdAt: Double,
        lastUsedAt: Double?
    ) {
        self.id = id
        self.text = text
        self.image = image
        self.name = name
        self.memo = memo
        self.isPinned = isPinned
        self.createdAt = createdAt
        self.lastUsedAt = lastUsedAt
    }
}

public struct ClipBridgeChange: Sendable {
    public enum Kind: String, Sendable {
        case updated
        case deleted
    }

    public let kind: Kind
    public let id: UUID

    public init(
        kind: Kind,
        id: UUID
    ) {
        self.kind = kind
        self.id = id
    }
}

public enum ClipBridgeCopyResult: String, Sendable {
    case copied
    case copiedWithoutLastUsedAt
    case writeNotObserved
}

public enum ClipBridgePhotoSaveResult: String, Sendable {
    case saved
    case denied
    case restricted
}

public enum ClipBridgeError: Error, Sendable {
    case invalidID
    case unavailable
    case copyFailed
    case writeFailed
    case readFailed
    case corruptedData
    case photoSaveFailed
    case imageUnavailable

    var code: String {
        switch self {
        case .invalidID: "E_INVALID_ID"
        case .unavailable: "E_UNAVAILABLE"
        case .copyFailed: "E_COPY_FAILED"
        case .writeFailed: "E_WRITE_FAILED"
        case .readFailed: "E_READ_FAILED"
        case .corruptedData: "E_CORRUPTED_DATA"
        case .photoSaveFailed: "E_PHOTO_SAVE_FAILED"
        case .imageUnavailable: "E_IMAGE_UNAVAILABLE"
        }
    }
}

public protocol ClipBridgeProvider: Sendable {
    func changes() async -> AsyncStream<ClipBridgeChange>
    func getClipImagePreview(id: UUID) async throws -> String?
    func saveClipImageToPhotos(id: UUID) async throws -> ClipBridgePhotoSaveResult?
    func clip(id: UUID) async throws -> ClipBridgeRecord?
    func updateClip(
        id: UUID,
        name: String?,
        memo: String?,
        isPinned: Bool
    ) async throws -> ClipBridgeRecord?
    func deleteClip(id: UUID) async throws
    func copyClip(id: UUID) async throws -> ClipBridgeCopyResult?
}

@MainActor
public enum ClipBridge {
    static var provider: (any ClipBridgeProvider)?

    private static var changesTask: Task<Void, Never>?
    private static var registration: (id: UUID, emit: @Sendable (String, String) -> Void)?

    public static func register(_ provider: any ClipBridgeProvider) {
        changesTask?.cancel()
        self.provider = provider
        changesTask = Task { @MainActor in
            let changes = await provider.changes()
            for await change in changes {
                guard !Task.isCancelled else { return }
                registration?.emit(change.kind.rawValue, change.id.uuidString)
            }
        }
    }

    static func register(
        id: UUID,
        emit: @escaping @Sendable (String, String) -> Void
    ) {
        registration = (id, emit)
    }

    static func unregister(id: UUID) {
        if registration?.id == id { registration = nil }
    }

    public static func unregister() {
        changesTask?.cancel()
        changesTask = nil
        provider = nil
    }
}
