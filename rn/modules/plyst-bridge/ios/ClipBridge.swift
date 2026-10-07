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

public enum ClipBridgeError: Error, Sendable {
    case invalidID
    case unavailable
    case readFailed
    case corruptedData
    case imageUnavailable

    var code: String {
        switch self {
        case .invalidID: "E_INVALID_ID"
        case .unavailable: "E_UNAVAILABLE"
        case .readFailed: "E_READ_FAILED"
        case .corruptedData: "E_CORRUPTED_DATA"
        case .imageUnavailable: "E_IMAGE_UNAVAILABLE"
        }
    }
}

public protocol ClipBridgeProvider: Sendable {
    func clip(id: UUID) async throws -> ClipBridgeRecord?
}

@MainActor
public enum ClipBridge {
    static var provider: (any ClipBridgeProvider)?

    public static func register(_ provider: any ClipBridgeProvider) {
        self.provider = provider
    }

    public static func unregister() {
        provider = nil
    }
}
