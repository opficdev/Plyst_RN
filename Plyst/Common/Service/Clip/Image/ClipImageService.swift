//
//  ClipImageService.swift
//  Plyst
//
//  Created by opfic on 9/29/26.
//

import Foundation
import PlystCore

/// 같은 루트의 이미지 쓰기와 복구는 코어의 ClipImageOperations가 조율
/// 이 타입은 실행 위치, 값 변환, 오류 변환, 원본 읽기를 담당
/// 별도 프로세스의 변경은 조율하지 않음
///
/// `ShareInboxImages`는 두 프로세스가 다룸
/// 저장과 `recoverPendingCleanup`은 Share Extension만 실행
/// 본 앱은 읽기와 `delete(id:)`만 실행
/// 본 앱이 복구를 실행하면 Extension이 저장 중이라 아직 참조되지 않은 파일을 지울 수 있음
/// `<fileID>/preview`와 `<fileID>/thumbnail-<px>`는 원본에서 다시 만들 수 있는 파생 파일
/// 본 앱 이미지 루트에서만 생성하며 `ShareInboxImages`에서는 생성하지 않음
actor ClipImageService {
    private let queue = DispatchSerialQueue(label: "opfic.Plyst.ClipImageService")
    let core: ClipImageOperations

    /// 코어 잠금 대기가 협력 스레드를 막지 않도록 전용 직렬 큐에서 실행
    nonisolated var unownedExecutor: UnownedSerialExecutor { queue.asUnownedSerialExecutor() }

    init(
        storage: SQLiteClipStorageService,
        rootURL: URL
    ) throws {
        guard rootURL.isFileURL, !rootURL.path.contains("\0") else { throw ClipImageFileError.invalidRoot }
        let root = rootURL.standardizedFileURL.resolvingSymlinksInPath().path
        core = try clipCoreCall(fallback: ClipImageFileError.writeFailed) { _ in
            try ClipImageOperations.open(store: storage.store, root: root, codec: ClipImageCodec())
        }
    }

    func saveImage(
        _ data: Data,
        id: Clip.ID = UUID(),
        name: String? = nil,
        memo: String? = nil,
        pinnedAt: Date? = nil,
        createdAt: Date = Date()
    ) throws -> ClipImageMutationResult<Clip> {
        let properties = try ClipImageCodec.validated(data)
        let draft = ClipImageDraftValue(
            id: id.uuidString,
            name: name,
            memo: memo,
            pinnedAt: pinnedAt?.timeIntervalSinceReferenceDate,
            createdAt: createdAt.timeIntervalSinceReferenceDate
        )
        let saved = try clipCoreCall(fallback: ClipImageFileError.writeFailed) {
            try core.saveImage(data: data, properties: properties, draft: draft, cancellation: $0)
        }
        guard let clip = Clip(coreValue: saved.clip) else { throw ClipStorageError.corruptedData }
        return ClipImageMutationResult(value: clip, cleanup: ClipImageCleanupState(coreValue: saved.cleanup))
    }

    /// 클립을 재조회하지 않고 전달받은 메타데이터에 대응하는 원본을 검증
    func loadImage(_ image: ClipImageMetadata) throws -> Data {
        let path = try clipCoreCall(fallback: ClipImageFileError.readFailed) {
            try core.loadImage(image: image.coreValue, cancellation: $0)
        }
        // 이 actor의 다른 작업이 끼어들 수 없으므로 삭제와 섞이지 않음
        do { return try Data(contentsOf: URL(fileURLWithPath: path)) } catch { throw ClipImageFileError.readFailed }
    }

    /// 본 앱 이미지 루트에서만 호출
    /// 삭제와 직렬화하여 원본에서 미리보기 파일을 매번 다시 만듦
    func makePreviewFileURL(_ image: ClipImageMetadata) throws -> URL {
        let path = try clipCoreCall(fallback: ClipImageFileError.writeFailed) {
            try core.makePreview(image: image.coreValue, cancellation: $0)
        }
        return URL(fileURLWithPath: path)
    }

    /// 본 앱 이미지 루트에서만 호출
    /// 삭제와 직렬화하여 요청한 크기의 썸네일 파일을 매번 다시 만듦
    func makeThumbnailFileURL(
        _ image: ClipImageMetadata,
        maximumPixelDimension: Int
    ) throws -> URL {
        let path = try clipCoreCall(fallback: ClipImageFileError.writeFailed) {
            try core.makeThumbnail(
                image: image.coreValue,
                maximumPixelDimension: Int64(maximumPixelDimension),
                cancellation: $0
            )
        }
        return URL(fileURLWithPath: path)
    }

    /// DB 삭제 확정 후 파일 정리에 실패해도 확정된 삭제를 실패로 반환하지 않음
    func delete(id: Clip.ID) throws -> ClipImageMutationResult<Clip.ID> {
        let cleanup = try clipCoreCall(fallback: ClipStorageError.writeFailed) {
            try core.deleteClip(id: id.uuidString, cancellation: $0)
        }
        return ClipImageMutationResult(value: id, cleanup: ClipImageCleanupState(coreValue: cleanup))
    }

    /// 초기화 이후 명시적으로 호출
    /// 이번에 정리하지 못한 fileID만 반환
    /// DB 조회에 실패하면 후보를 변경하지 않고 오류를 반환
    func recoverPendingCleanup() throws -> [UUID] {
        try clipCoreCall(fallback: ClipImageFileError.deleteFailed) {
            try core.recoverPendingCleanup(cancellation: $0)
        }.compactMap(UUID.init(uuidString:))
    }
}
