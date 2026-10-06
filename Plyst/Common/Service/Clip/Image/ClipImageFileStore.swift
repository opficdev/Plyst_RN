//
//  ClipImageFileStore.swift
//  Plyst
//
//  Created by opfic on 9/29/26.
//

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// 주입한 전용 루트에서 원본 바이트를 관리합니다. 같은 루트의 변경은 ClipImageService 하나가 조율해야 합니다.
/// `ShareInboxImages`는 예외입니다. 저장과 정리 복구는 Share Extension만 실행하고 본 앱은 읽기와 삭제만 실행합니다.
struct ClipImageFileStore: Sendable {
    /// 저장 전 검증에서 축소 디코딩하는 긴 변의 최대 픽셀 수입니다. 검증이 원본 해상도 비트맵을 만들지 않게 합니다.
    private static let validationPixelDimension = 64

    private let root: URL

    init(rootURL: URL) throws {
        guard rootURL.isFileURL, !rootURL.path.contains("\0") else { throw ClipImageFileError.invalidRoot }
        root = rootURL.standardizedFileURL.resolvingSymlinksInPath()
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        } catch {
            throw ClipImageFileError.writeFailed
        }
        try validateRoot()
    }

    /// 검증한 원본을 재인코딩 없이 저장합니다. 반환된 fileID의 정리 후보는 메타데이터 저장 확정 후 해제해야 합니다.
    func save(_ data: Data) throws -> ClipImageMetadata {
        let properties = try imageProperties(data)
        try validateRoot()
        var fileID = UUID()
        while try attributes(at: url(for: fileID)) != nil { fileID = UUID() }
        let directory = url(for: fileID)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
            try markPending(fileID: fileID)
            try data.write(to: directory.appendingPathComponent("original"), options: .atomic)
        } catch {
            // 원자적 쓰기의 임시 파일까지 함께 정리합니다. 실패한 정리는 후보 또는 불완전한 디렉터리로 남습니다.
            try? delete(fileID: fileID)
            throw ClipImageFileError.writeFailed
        }
        return ClipImageMetadata(
            fileID: fileID,
            contentType: properties.type,
            pixelWidth: properties.size.width,
            pixelHeight: properties.size.height,
            byteCount: data.count
        )
    }

    func load(fileID: UUID) throws -> Data {
        guard let directory = try directory(for: fileID) else { throw ClipImageFileError.notFound(fileID) }
        let original = directory.appendingPathComponent("original")
        guard let attributes = try attributes(at: original) else { throw ClipImageFileError.notFound(fileID) }
        guard attributes[.type] as? FileAttributeType == .typeRegular else { throw ClipImageFileError.unsafePath }
        do { return try Data(contentsOf: original) } catch { throw ClipImageFileError.readFailed }
    }

    /// 저장된 메타데이터와 원본을 대조하며 파일이나 이미지 표현을 변경하지 않습니다.
    func load(image: ClipImageMetadata) throws -> Data {
        try Task.checkCancellation()
        let data = try load(fileID: image.fileID)
        guard data.count == image.byteCount else { throw ClipImageFileError.corruptedImage(image.fileID) }
        do {
            let properties = try imageProperties(data)
            guard properties.type == image.contentType,
                  properties.size.width == image.pixelWidth,
                  properties.size.height == image.pixelHeight else { throw ClipImageFileError.corruptedImage(image.fileID) }
            return data
        } catch let error as ClipImageFileError where error == .invalidImage || error == .unsupportedImage {
            throw ClipImageFileError.corruptedImage(image.fileID)
        }
    }

    /// 원본을 Data로 적재하지 않고 첫 프레임을 표시 크기로 축소합니다. 저장된 파일은 변경하지 않습니다.
    func loadThumbnail(
        image: ClipImageMetadata,
        maximumPixelDimension: Int
    ) throws -> Data {
        try Task.checkCancellation()
        guard 0 < maximumPixelDimension else { throw ClipImageFileError.readFailed }
        guard let directory = try directory(for: image.fileID) else {
            throw ClipImageFileError.notFound(image.fileID)
        }
        let original = directory.appendingPathComponent("original")
        guard let attributes = try attributes(at: original) else {
            throw ClipImageFileError.notFound(image.fileID)
        }
        guard original.resolvingSymlinksInPath().standardizedFileURL == original.standardizedFileURL else {
            throw ClipImageFileError.unsafePath
        }
        guard attributes[.type] as? FileAttributeType == .typeRegular else {
            throw ClipImageFileError.unsafePath
        }
        guard attributes[.size] as? Int == image.byteCount else {
            throw ClipImageFileError.corruptedImage(image.fileID)
        }
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(original as CFURL, options),
              CGImageSourceGetType(source) as String? == image.contentType,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as NSDictionary?,
              properties[kCGImagePropertyPixelWidth] as? Int == image.pixelWidth,
              properties[kCGImagePropertyPixelHeight] as? Int == image.pixelHeight else {
            throw ClipImageFileError.corruptedImage(image.fileID)
        }
        let thumbnailOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixelDimension
        ] as CFDictionary
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions),
              CGImageSourceGetStatusAtIndex(source, 0) == .statusComplete,
              let output = CFDataCreateMutable(nil, 0),
              let destination = CGImageDestinationCreateWithData(
                output,
                UTType.png.identifier as CFString,
                1,
                nil
              ) else {
            throw ClipImageFileError.corruptedImage(image.fileID)
        }
        try Task.checkCancellation()
        CGImageDestinationAddImage(destination, thumbnail, nil)
        guard CGImageDestinationFinalize(destination) else { throw ClipImageFileError.readFailed }
        return output as Data
    }

    /// 이미 존재하지 않는 파일은 삭제된 것으로 처리합니다.
    func delete(fileID: UUID) throws {
        guard let directory = try directory(for: fileID) else { return }
        do {
            let original = directory.appendingPathComponent("original")
            if try attributes(at: original) != nil { try FileManager.default.removeItem(at: original) }
            let entries = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            for entry in entries where entry.lastPathComponent != "pending" {
                try FileManager.default.removeItem(at: entry)
            }
            // 원본과 임시 파일이 모두 제거된 후에만 정리 기록을 해제합니다.
            try finishPending(fileID: fileID)
            // 여기서 중단되면 원본이 없는 디렉터리를 복구 후보로 찾을 수 있습니다.
            try FileManager.default.removeItem(at: directory)
        } catch { throw ClipImageFileError.deleteFailed }
    }

    func markPending(fileID: UUID) throws {
        guard let directory = try directory(for: fileID) else { return }
        let marker = directory.appendingPathComponent("pending")
        try validateFile(at: marker)
        do { try Data().write(to: marker, options: .atomic) } catch { throw ClipImageFileError.writeFailed }
    }

    func finishPending(fileID: UUID) throws {
        guard let directory = try directory(for: fileID) else { return }
        let marker = directory.appendingPathComponent("pending")
        guard try attributes(at: marker) != nil else { return }
        try validateFile(at: marker)
        do { try FileManager.default.removeItem(at: marker) } catch { throw ClipImageFileError.deleteFailed }
    }

    /// 정상 원본을 일괄 삭제하지 않고, 정리 후보와 저장 중단으로 불완전한 디렉터리만 반환합니다.
    func pendingFileIDs() throws -> [UUID] {
        try validateRoot()
        let entries: [URL]
        do {
            entries = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        } catch { throw ClipImageFileError.readFailed }
        var ids = [UUID]()
        for entry in entries {
            guard let fileID = UUID(uuidString: entry.lastPathComponent), fileID.uuidString == entry.lastPathComponent,
                  let directory = try directory(for: fileID) else { continue }
            let marker = directory.appendingPathComponent("pending")
            try validateFile(at: marker)
            if try attributes(at: marker) != nil || attributes(at: directory.appendingPathComponent("original")) == nil {
                ids.append(fileID)
            }
        }
        return ids.sorted { $0.uuidString < $1.uuidString }
    }

    private func imageProperties(_ data: Data) throws -> (type: String, size: (width: Int, height: Int)) {
        try Task.checkCancellation()
        guard !data.isEmpty, let source = CGImageSourceCreateWithData(data as CFData, nil),
              let identifier = CGImageSourceGetType(source) else { throw ClipImageFileError.invalidImage }
        let type = identifier as String
        let supported = CGImageSourceCopyTypeIdentifiers() as? [String] ?? []
        guard supported.contains(type), UTType(type)?.conforms(to: .image) == true else { throw ClipImageFileError.unsupportedImage }
        // ImageIO는 잘린 GIF도 남은 프레임만으로 statusComplete를 반환하므로 종료 바이트(0x3B)로 잘림을 판별합니다.
        if type == UTType.gif.identifier, data.last != 0x3B { throw ClipImageFileError.invalidImage }
        let count = CGImageSourceGetCount(source)
        guard 0 < count else { throw ClipImageFileError.invalidImage }
        // 원본 해상도 비트맵을 만들지 않도록 크기는 속성으로 읽고 무결성은 축소 디코딩으로 확인합니다.
        let validationOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: Self.validationPixelDimension
        ] as CFDictionary
        var size = (width: 0, height: 0)
        for index in 0..<count {
            try Task.checkCancellation()
            // 프레임마다 즉시 디코딩하고 캐시를 해제하여 모든 프레임의 픽셀을 동시에 보관하지 않습니다.
            let dimensions = try autoreleasepool {
                defer { CGImageSourceRemoveCacheAtIndex(source, index) }
                guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as NSDictionary?,
                      let width = properties[kCGImagePropertyPixelWidth] as? Int,
                      let height = properties[kCGImagePropertyPixelHeight] as? Int,
                      0 < width, 0 < height,
                      CGImageSourceCreateThumbnailAtIndex(source, index, validationOptions) != nil,
                      CGImageSourceGetStatusAtIndex(source, index) == .statusComplete else { throw ClipImageFileError.invalidImage }
                return (width: width, height: height)
            }
            if index == 0 { size = dimensions }
        }
        guard CGImageSourceGetStatus(source) == .statusComplete else { throw ClipImageFileError.invalidImage }
        return (type, size)
    }

    private func url(for fileID: UUID) -> URL {
        root.appendingPathComponent(fileID.uuidString, isDirectory: true)
    }

    private func directory(for fileID: UUID) throws -> URL? {
        try validateRoot()
        let directory = url(for: fileID)
        guard let attributes = try attributes(at: directory) else { return nil }
        guard attributes[.type] as? FileAttributeType == .typeDirectory,
              directory.resolvingSymlinksInPath().standardizedFileURL == directory.standardizedFileURL else {
            throw ClipImageFileError.unsafePath
        }
        return directory
    }

    private func validateRoot() throws {
        guard let attributes = try attributes(at: root), attributes[.type] as? FileAttributeType == .typeDirectory,
              root.resolvingSymlinksInPath().standardizedFileURL == root.standardizedFileURL else { throw ClipImageFileError.unsafePath }
    }

    private func validateFile(at url: URL) throws {
        if let attributes = try attributes(at: url), attributes[.type] as? FileAttributeType != .typeRegular {
            throw ClipImageFileError.unsafePath
        }
    }

    private func attributes(at url: URL) throws -> [FileAttributeKey: Any]? {
        do {
            return try FileManager.default.attributesOfItem(atPath: url.path)
        } catch {
            let error = error as NSError
            if error.domain == NSCocoaErrorDomain,
               error.code == CocoaError.fileNoSuchFile.rawValue || error.code == CocoaError.fileReadNoSuchFile.rawValue { return nil }
            throw ClipImageFileError.readFailed
        }
    }
}
