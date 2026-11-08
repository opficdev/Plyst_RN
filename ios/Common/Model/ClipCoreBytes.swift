//
//  ClipCoreBytes.swift
//  Plyst
//
//  Created by opfic on 11/6/26.
//

import Foundation

/// ClipStore.fetchAllEncoded 버퍼의 해석
/// 형식은 core/src/store/wire.rs가 소유
extension Clip {
    /// 버퍼가 형식과 맞지 않으면 nil
    static func list(coreBytes data: Data) -> [Clip]? {
        data.withUnsafeBytes { bytes in
            var reader = ClipCoreBytesReader(bytes: bytes)
            var clips = [Clip]()
            while !reader.isAtEnd {
                guard let clip = reader.clip() else { return nil }
                clips.append(clip)
            }
            return clips
        }
    }
}

private enum ClipCoreBytesFlag {
    static let image: UInt8 = 1
    static let name: UInt8 = 1 << 1
    static let pinnedAt: UInt8 = 1 << 2
    static let memo: UInt8 = 1 << 3
    static let lastUsedAt: UInt8 = 1 << 4
}

private struct ClipCoreBytesReader {
    let bytes: UnsafeRawBufferPointer
    private var offset = 0

    init(bytes: UnsafeRawBufferPointer) {
        self.bytes = bytes
    }

    var isAtEnd: Bool { offset == bytes.count }

    mutating func clip() -> Clip? {
        guard let id = uuid(),
              let flags = load(UInt8.self),
              let createdAt = date(),
              let content = content(isImage: flags & ClipCoreBytesFlag.image != 0) else { return nil }
        var name: String?
        var pinnedAt: Date?
        var memo: String?
        var lastUsedAt: Date?
        if flags & ClipCoreBytesFlag.name != 0 {
            guard let value = string() else { return nil }
            name = value
        }
        if flags & ClipCoreBytesFlag.pinnedAt != 0 {
            guard let value = date() else { return nil }
            pinnedAt = value
        }
        if flags & ClipCoreBytesFlag.memo != 0 {
            guard let value = string() else { return nil }
            memo = value
        }
        if flags & ClipCoreBytesFlag.lastUsedAt != 0 {
            guard let value = date() else { return nil }
            lastUsedAt = value
        }
        return Clip(
            id: id,
            content: content,
            name: name,
            pinnedAt: pinnedAt,
            memo: memo,
            createdAt: createdAt,
            lastUsedAt: lastUsedAt
        )
    }

    private mutating func content(isImage: Bool) -> ClipContent? {
        guard isImage else { return string().map(ClipContent.text) }
        guard let fileID = uuid(),
              let pixelWidth = load(Int64.self),
              let pixelHeight = load(Int64.self),
              let byteCount = load(Int64.self),
              let contentType = string() else { return nil }
        return .image(ClipImageMetadata(
            fileID: fileID,
            contentType: contentType,
            pixelWidth: Int(Int64(littleEndian: pixelWidth)),
            pixelHeight: Int(Int64(littleEndian: pixelHeight)),
            byteCount: Int(Int64(littleEndian: byteCount))
        ))
    }

    private mutating func load<Value: BitwiseCopyable>(_ type: Value.Type) -> Value? {
        let size = MemoryLayout<Value>.size
        guard offset + size <= bytes.count else { return nil }
        defer { offset += size }
        return bytes.loadUnaligned(fromByteOffset: offset, as: type)
    }

    private mutating func uuid() -> UUID? {
        load(uuid_t.self).map(UUID.init(uuid:))
    }

    private mutating func date() -> Date? {
        load(UInt64.self).map { Date(timeIntervalSinceReferenceDate: Double(bitPattern: UInt64(littleEndian: $0))) }
    }

    private mutating func string() -> String? {
        guard let raw = load(UInt32.self) else { return nil }
        let end = offset + Int(UInt32(littleEndian: raw))
        guard end <= bytes.count else { return nil }
        defer { offset = end }
        let source = bytes[offset..<end]
        return String(unsafeUninitializedCapacity: source.count) { target in
            UnsafeMutableRawBufferPointer(target).copyBytes(from: source)
            return source.count
        }
    }
}
