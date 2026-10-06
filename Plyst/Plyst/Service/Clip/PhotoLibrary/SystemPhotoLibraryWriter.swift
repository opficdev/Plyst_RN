//
//  SystemPhotoLibraryWriter.swift
//  Plyst
//
//  Created by opfic on 10/1/26.
//

import Foundation
import Photos
import UniformTypeIdentifiers

struct SystemPhotoLibraryWriter: PhotoLibraryWriter {
    @concurrent
    func requestAddAuthorization() async throws -> PhotoLibraryAuthorization {
        try Task.checkCancellation()
        var status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        if status == .notDetermined {
            status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        }
        try Task.checkCancellation()
        switch status {
        case .authorized, .limited:
            return .authorized
        case .restricted:
            return .restricted
        case .denied, .notDetermined:
            return .denied
        @unknown default:
            return .denied
        }
    }

    @concurrent
    func write(
        _ data: Data,
        contentType: String
    ) async throws {
        try Task.checkCancellation()
        try await PHPhotoLibrary.shared().performChanges {
            let options = PHAssetResourceCreationOptions()
            if #available(iOS 26.0, *) {
                options.contentType = UTType(contentType)
            } else {
                options.uniformTypeIdentifier = contentType
            }
            let request = PHAssetCreationRequest.forAsset()
            request.addResource(with: .photo, data: data, options: options)
        }
    }
}
