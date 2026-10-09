//
//  ClipImageService.swift
//  Plyst
//
//  Created by opfic on 9/29/26.
//

import Foundation

/// 같은 루트의 이미지 쓰기와 복구를 하나의 인스턴스에서 조율합니다. 별도 프로세스의 변경은 조율하지 않습니다.
///
/// `ShareInboxImages`는 두 프로세스가 다룹니다. 저장과 `recoverPendingCleanup`은 Share Extension만 실행합니다.
/// 본 앱은 읽기와 `delete(id:)`만 실행합니다. 본 앱이 복구를 실행하면 Extension이 저장 중이라 아직 참조되지 않은 파일을 지울 수 있습니다.
/// `<fileID>/preview`는 원본에서 다시 만들 수 있는 파생 파일입니다. 본 앱 이미지 루트에서만 생성하며 `ShareInboxImages`에서는 생성하지 않습니다.
actor ClipImageService {
    private static let previewPixelDimension = 1600
    private let storage: any ClipStorageService
    private let files: ClipImageFileStore
    private var isBusy = false
    private var waiters = [CheckedContinuation<Void, Never>]()

    init(
        storage: any ClipStorageService,
        files: ClipImageFileStore
    ) {
        self.storage = storage
        self.files = files
    }

    func saveImage(
        _ data: Data,
        id: Clip.ID = UUID(),
        name: String? = nil,
        memo: String? = nil,
        isPinned: Bool = false,
        createdAt: Date = Date()
    ) async throws -> ClipImageMutationResult<Clip> {
        try await acquire()
        defer { release() }
        let image = try files.save(data)
        let clip = Clip(
            id: id,
            content: .image(image),
            name: name,
            isPinned: isPinned,
            memo: memo,
            createdAt: createdAt
        )
        do {
            try await storage.insert(clip)
        } catch {
            try? files.delete(fileID: image.fileID)
            throw error
        }
        let cleanup: ClipImageCleanupState
        do {
            try files.finishPending(fileID: image.fileID)
            cleanup = .completed
        } catch {
            cleanup = .pending(image.fileID)
        }
        return ClipImageMutationResult(value: clip, cleanup: cleanup)
    }

    func loadImage(id: Clip.ID) async throws -> Data {
        try await acquire()
        defer { release() }
        guard let clip = try await storage.fetch(id: id) else { throw ClipStorageError.notFound(id) }
        guard case .image(let image) = clip.content else { throw ClipImageFileError.notImage(id) }
        return try files.load(image: image)
    }

    /// 클립을 재조회하지 않고 전달받은 메타데이터에 대응하는 원본을 검증합니다.
    func loadImage(_ image: ClipImageMetadata) async throws -> Data {
        try await acquire()
        defer { release() }
        return try files.load(image: image)
    }

    /// 본 앱 이미지 루트에서만 호출합니다. 삭제와 직렬화하여 원본에서 미리보기 파일을 매번 다시 만듭니다.
    func makePreviewFileURL(_ image: ClipImageMetadata) async throws -> URL {
        try await acquire()
        defer { release() }
        return try files.writePreview(image: image, maximumPixelDimension: Self.previewPixelDimension)
    }

    /// 반환 URL은 `delete(id:)` 전까지만 유효한 읽기 전용 참조입니다. 호출부는 파일을 쓰거나 옮기지 않아야 합니다.
    /// 이후 읽기에 실패하면 파일이 삭제된 것으로 처리해야 합니다.
    func loadImageFileURL(_ image: ClipImageMetadata) async throws -> URL {
        try await acquire()
        defer { release() }
        return try files.fileURL(image: image)
    }

    /// 카드 표시용 축소 데이터만 반환하며 원본 파일은 유지합니다.
    func loadThumbnail(
        _ image: ClipImageMetadata,
        maximumPixelDimension: Int
    ) async throws -> Data {
        try await acquire()
        defer { release() }
        return try files.loadThumbnail(image: image, maximumPixelDimension: maximumPixelDimension)
    }

    /// DB 삭제 확정 후 파일 정리에 실패해도 확정된 삭제를 실패로 반환하지 않습니다.
    func delete(id: Clip.ID) async throws -> ClipImageMutationResult<Clip.ID> {
        try await acquire()
        defer { release() }
        guard let clip = try await storage.fetch(id: id) else { throw ClipStorageError.notFound(id) }
        if case .image(let image) = clip.content { try files.markPending(fileID: image.fileID) }
        try await storage.delete(id: id)
        var cleanup = ClipImageCleanupState.completed
        if case .image(let image) = clip.content { cleanup = await clean(fileID: image.fileID) }
        return ClipImageMutationResult(value: id, cleanup: cleanup)
    }

    /// 초기화 이후 명시적으로 호출합니다. 이번에 정리하지 못한 fileID만 반환합니다.
    /// DB 조회에 실패하면 후보를 변경하지 않고 오류를 반환합니다.
    func recoverPendingCleanup() async throws -> [UUID] {
        try await acquire()
        defer { release() }
        let candidates = try files.pendingFileIDs()
        guard !candidates.isEmpty else { return [] }
        let references = try await imageReferences()
        var pending = [UUID]()
        for fileID in candidates {
            do {
                try clean(fileID: fileID, referenced: references.contains(fileID))
            } catch { pending.append(fileID) }
        }
        return pending
    }

    private func imageReferences() async throws -> Set<UUID> {
        let clips = try await storage.fetchAll(order: .createdAt)
        return Set(clips.compactMap { clip in
            guard case .image(let image) = clip.content else { return nil }
            return image.fileID
        })
    }

    private func clean(fileID: UUID) async -> ClipImageCleanupState {
        do {
            let references = try await imageReferences()
            try clean(fileID: fileID, referenced: references.contains(fileID))
            return .completed
        } catch {
            return .pending(fileID)
        }
    }

    private func clean(
        fileID: UUID,
        referenced: Bool
    ) throws {
        if referenced {
            try files.finishPending(fileID: fileID)
        } else { try files.delete(fileID: fileID) }
    }

    /// actor는 await 중에 재진입할 수 있으므로 외부 호출을 포함한 작업 전체의 순서를 보호합니다.
    private func acquire() async throws {
        try Task.checkCancellation()
        if isBusy {
            await withCheckedContinuation { waiters.append($0) }
        } else {
            isBusy = true
        }
        do {
            try Task.checkCancellation()
        } catch {
            release()
            throw error
        }
    }

    private func release() {
        if waiters.isEmpty {
            isBusy = false
        } else { waiters.removeFirst().resume() }
    }
}
