//
//  ClipPhotoLibraryService.swift
//  Plyst
//
//  Created by opfic on 10/1/26.
//

import Foundation

enum ClipPhotoLibrarySaveResult: Equatable, Sendable {
    case saved
    case denied
    case restricted
}

/// 명시적인 사용자 요청에서만 사진 앱에 원본을 추가합니다. storage와 images는 같은 저장소를 사용합니다.
struct ClipPhotoLibraryService: Sendable {
    private let storage: any ClipStorageService
    private let images: ClipImageService
    private let writer: any PhotoLibraryWriter

    init(
        storage: any ClipStorageService,
        images: ClipImageService,
        writer: any PhotoLibraryWriter = SystemPhotoLibraryWriter()
    ) {
        self.storage = storage
        self.images = images
        self.writer = writer
    }

    /// 권한 대기 중에는 이미지 서비스의 작업 순서를 점유하지 않습니다.
    func save(id: Clip.ID) async throws -> ClipPhotoLibrarySaveResult {
        try Task.checkCancellation()
        switch try await writer.requestAddAuthorization() {
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        case .authorized:
            break
        }
        try Task.checkCancellation()
        guard let clip = try await storage.fetch(id: id) else { throw ClipStorageError.notFound(id) }
        guard case .image(let image) = clip.content else { throw ClipImageFileError.notImage(id) }
        let data = try await images.loadImage(image)
        try Task.checkCancellation()
        try await writer.write(data, contentType: image.contentType)
        // 쓰기 확정 이후에는 취소를 다시 확인하지 않습니다.
        return .saved
    }
}
