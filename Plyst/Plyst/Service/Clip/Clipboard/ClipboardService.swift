//
//  ClipboardService.swift
//  Plyst
//
//  Created by opfic on 9/29/26.
//

import Foundation

enum ClipboardSaveResult: Equatable, Sendable {
    case saved(Clip)
    /// 이미지 원본과 클립 기록은 저장됐지만 pending 표시 파일을 제거하지 못했습니다.
    /// recoverPendingCleanup()을 호출해야 정리를 다시 시도합니다.
    case savedWithPendingCleanup(Clip, fileID: UUID)
    case empty
    case unsupported
    case accessFailed
    case invalidImage
}

/// 사용자 요청에 따라 클립을 저장하거나 다시 복사합니다. 초기화 시에는 클립보드에 접근하지 않습니다.
/// storage와 images는 같은 저장소를 사용해야 합니다.
/// 같은 클립보드를 사용하는 호출부는 이 서비스 하나와 이미지 루트별 ClipImageService 하나를 공유해야 합니다.
actor ClipboardService {
    private let storage: any ClipStorageService
    private let images: ClipImageService
    private let reader: any ClipboardReader
    private let writer: any ClipboardWriter
    private var isBusy = false
    private var waiters = [CheckedContinuation<Void, Never>]()

    init(
        storage: any ClipStorageService,
        images: ClipImageService,
        reader: any ClipboardReader = SystemClipboardReader(),
        writer: any ClipboardWriter = SystemClipboardWriter(localOnly: true, expirationDate: nil)
    ) {
        self.storage = storage
        self.images = images
        self.reader = reader
        self.writer = writer
    }

    /// 저장소 오류와 CancellationError는 그대로 전파합니다. 저장 확정 이후에는 취소를 다시 확인하지 않습니다.
    func saveCurrentClipboard() async throws -> ClipboardSaveResult {
        try await acquire()
        defer { release() }
        switch try await reader.read() {
        case .text(let text):
            let content = ClipContent.text(text)
            guard content.isValid else { return .empty }
            try Task.checkCancellation()
            let clip = Clip(content: content)
            try await storage.insert(clip)
            return .saved(clip)
        case .image(let data):
            try Task.checkCancellation()
            do {
                let result = try await images.saveImage(data)
                switch result.cleanup {
                case .completed:
                    return .saved(result.value)
                case .pending(let fileID):
                    return .savedWithPendingCleanup(result.value, fileID: fileID)
                }
            } catch let error as ClipImageFileError {
                switch error {
                case .invalidImage:
                    return .invalidImage
                case .unsupportedImage:
                    return .unsupported
                default:
                    throw error
                }
            }
        case .empty:
            return .empty
        case .unsupported:
            return .unsupported
        case .accessFailed:
            return .accessFailed
        }
    }

    /// 쓰기 전 오류는 전파합니다. 쓰기가 확인된 이후의 사용 시각 저장 실패는 부분 성공으로 반환합니다.
    func copy(id: Clip.ID) async throws -> ClipboardCopyResult {
        try await acquire()
        defer { release() }
        guard let clip = try await storage.fetch(id: id) else { throw ClipStorageError.notFound(id) }
        let content = try await clipboardContent(for: clip)
        try Task.checkCancellation()
        guard try await writer.write(content) == .observed else { return .writeNotObserved(id) }
        let copiedAt = Date()
        do {
            let updated = try await storage.update(id: id, change: .lastUsedAt(copiedAt, matching: clip))
            guard updated.id == clip.id,
                  updated.content == clip.content,
                  updated.createdAt == clip.createdAt else {
                return .copiedWithoutLastUsedAt(
                    clip: clip,
                    copiedAt: copiedAt,
                    failure: .replaced
                )
            }
            // 갱신 확정 뒤 발생한 취소로 완료된 복사와 사용 기록을 숨기지 않습니다.
            return .copied(updated)
        } catch {
            let failure: ClipboardUsageUpdateFailure
            if error is CancellationError {
                failure = .cancelled
            } else if let error = error as? ClipStorageError {
                failure = .storage(error)
            } else {
                failure = .unknown
            }
            return .copiedWithoutLastUsedAt(
                clip: clip,
                copiedAt: copiedAt,
                failure: failure
            )
        }
    }

    private func clipboardContent(for clip: Clip) async throws -> ClipboardWriteContent {
        switch clip.content {
        case .text(let text):
            return .text(text)
        case .image(let image):
            // 같은 클립 식별자가 재사용돼도 최초 조회한 메타데이터와 다른 원본을 섞지 않습니다.
            let data = try await images.loadImage(image)
            return .image(data: data, contentType: image.contentType)
        }
    }

    /// actor의 재진입과 별개로 저장과 복사 작업 전체를 순서대로 처리합니다.
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
