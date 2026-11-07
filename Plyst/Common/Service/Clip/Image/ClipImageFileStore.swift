//
//  ClipImageFileStore.swift
//  Plyst
//
//  Created by opfic on 9/29/26.
//

import Foundation
import PlystCore

/// 주입한 전용 루트에서 원본 바이트를 관리
/// 파일 규칙은 코어의 ClipImageFiles가 소유하고 이 타입은 취소, 오류 변환, 원본 읽기를 담당
/// 같은 루트의 변경은 ClipImageService 하나가 조율해야 함
/// `ShareInboxImages`는 예외
/// 저장과 정리 복구는 Share Extension만 실행하고 본 앱은 읽기와 삭제만 실행
/// 파생 파일은 본 앱 이미지 루트에서만 생성하며 `ShareInboxImages`에서는 생성하지 않음
struct ClipImageFileStore: Sendable {
    private let files: ClipImageFiles

    init(rootURL: URL) throws {
        guard rootURL.isFileURL, !rootURL.path.contains("\0") else { throw ClipImageFileError.invalidRoot }
        let root = rootURL.standardizedFileURL.resolvingSymlinksInPath().path
        files = try converted(fallback: .writeFailed) { try ClipImageFiles.open(root: root) }
    }

    /// 검증한 원본을 재인코딩 없이 저장
    /// 반환된 fileID의 정리 후보는 메타데이터 저장 확정 후 해제해야 함
    func save(_ data: Data) throws -> ClipImageMetadata {
        let properties = try ClipImageCodec.properties(of: data)
        // UniFFI 바이트 인자의 길이가 Int32이므로 초과분은 호출 전에 거부
        guard data.count <= Int32.max else { throw ClipImageFileError.writeFailed }
        let fileID = try converted(fallback: .writeFailed) { UUID(uuidString: try files.save(data: data)) }
        guard let fileID else { throw ClipImageFileError.writeFailed }
        return ClipImageMetadata(
            fileID: fileID,
            contentType: properties.type,
            pixelWidth: properties.size.width,
            pixelHeight: properties.size.height,
            byteCount: data.count
        )
    }

    func load(fileID: UUID) throws -> Data {
        let path = try converted(fallback: .readFailed) { try files.originalPath(fileId: fileID.uuidString) }
        do { return try Data(contentsOf: URL(fileURLWithPath: path)) } catch { throw ClipImageFileError.readFailed }
    }

    /// 저장된 메타데이터와 원본을 대조하며 파일이나 이미지 표현을 변경하지 않음
    func load(image: ClipImageMetadata) throws -> Data {
        try Task.checkCancellation()
        let data = try load(fileID: image.fileID)
        guard data.count == image.byteCount else { throw ClipImageFileError.corruptedImage(image.fileID) }
        do {
            let properties = try ClipImageCodec.properties(of: data)
            guard properties.type == image.contentType,
                  properties.size.width == image.pixelWidth,
                  properties.size.height == image.pixelHeight else { throw ClipImageFileError.corruptedImage(image.fileID) }
            return data
        } catch let error as ClipImageFileError where error == .invalidImage || error == .unsupportedImage {
            throw ClipImageFileError.corruptedImage(image.fileID)
        }
    }

    /// 원본을 Data로 적재하지 않고 첫 프레임을 표시 크기로 축소
    /// 저장된 파일은 변경하지 않음
    func loadThumbnail(
        image: ClipImageMetadata,
        maximumPixelDimension: Int
    ) throws -> Data {
        try Task.checkCancellation()
        guard 0 < maximumPixelDimension else { throw ClipImageFileError.readFailed }
        let path = try converted(fallback: .readFailed) {
            try files.validatedOriginalPath(fileId: image.fileID.uuidString, byteCount: Int64(image.byteCount))
        }
        return try ClipImageCodec.thumbnail(
            of: URL(fileURLWithPath: path),
            image: image,
            maximumPixelDimension: maximumPixelDimension
        )
    }

    /// 본 앱 이미지 루트에서만 호출
    /// 원본에서 만든 축소본을 매번 원자적으로 덮어씀
    func writePreview(
        image: ClipImageMetadata,
        maximumPixelDimension: Int
    ) throws -> URL {
        let data = try loadThumbnail(image: image, maximumPixelDimension: maximumPixelDimension)
        try Task.checkCancellation()
        return try converted(fallback: .writeFailed) {
            URL(fileURLWithPath: try files.writePreview(fileId: image.fileID.uuidString, data: data))
        }
    }

    /// 본 앱 이미지 루트에서만 호출
    /// 요청한 크기의 축소본을 매번 원자적으로 덮어씀
    func writeThumbnail(
        image: ClipImageMetadata,
        maximumPixelDimension: Int
    ) throws -> URL {
        let data = try loadThumbnail(image: image, maximumPixelDimension: maximumPixelDimension)
        try Task.checkCancellation()
        return try converted(fallback: .writeFailed) {
            let path = try files.writeThumbnail(
                fileId: image.fileID.uuidString,
                maximumPixelDimension: Int64(maximumPixelDimension),
                data: data
            )
            return URL(fileURLWithPath: path)
        }
    }

    /// 이미 존재하지 않는 파일은 삭제된 것으로 처리
    func delete(fileID: UUID) throws {
        try converted(fallback: .deleteFailed) { try files.delete(fileId: fileID.uuidString) }
    }

    func markPending(fileID: UUID) throws {
        try converted(fallback: .writeFailed) { try files.markPending(fileId: fileID.uuidString) }
    }

    func finishPending(fileID: UUID) throws {
        try converted(fallback: .deleteFailed) { try files.finishPending(fileId: fileID.uuidString) }
    }

    /// 정상 원본을 일괄 삭제하지 않음
    /// 정리 후보와 저장 중단으로 불완전한 디렉터리만 반환
    func pendingFileIDs() throws -> [UUID] {
        try converted(fallback: .readFailed) { try files.pendingFileIds() }.compactMap(UUID.init(uuidString:))
    }
}

/// 코어 오류를 저장소 오류로 변환
/// 패닉은 연산별 대체 오류로 전달
private func converted<T>(
    fallback: ClipImageFileError,
    _ body: () throws -> T
) throws -> T {
    do {
        return try body()
    } catch let error as ClipImageFilesError {
        throw fileError(error, fallback: fallback)
    } catch {
        throw fallback
    }
}

private func fileError(
    _ error: ClipImageFilesError,
    fallback: ClipImageFileError
) -> ClipImageFileError {
    switch error {
    case .InvalidRoot: .invalidRoot
    case .UnsafePath: .unsafePath
    case .ReadFailed: .readFailed
    case .WriteFailed: .writeFailed
    case .DeleteFailed: .deleteFailed
    case .NotFound(let fileId): UUID(uuidString: fileId).map(ClipImageFileError.notFound) ?? fallback
    case .SizeMismatch(let fileId): UUID(uuidString: fileId).map(ClipImageFileError.corruptedImage) ?? fallback
    }
}
