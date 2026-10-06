//
//  ClipShareService.swift
//  Plyst
//
//  Created by opfic on 10/1/26.
//

import Foundation
import os
import UniformTypeIdentifiers

/// 공유 시트로 받은 항목을 클립으로 저장합니다. 여러 항목은 다루지 않습니다.
///
/// 지원하는 첫 첨부가 이미지 형식을 가지면 변환 없이 원본 바이트를 이름 없는 이미지 클립으로 저장합니다.
/// 그 외에는 텍스트나 URL을 텍스트 클립으로 저장합니다.
/// 지원하는 첫 첨부가 URL 하나뿐이고 경로나 쿼리 값에 든 주소의 확장자가 이미지 형식이면 이미지를 내려받아 원본 URL을 메모로 둔 이미지 클립으로 저장합니다.
/// 내려받기나 이미지 검증에 실패하면 같은 URL을 텍스트 클립으로 저장하며 일반 페이지 링크는 네트워크 요청을 하지 않습니다.
/// 저장을 시도할 때마다 첨부를 다시 읽으므로 읽기 실패 후에도 같은 항목으로 다시 시도할 수 있습니다.
/// 읽기에 실패하면 저장소에 쓰지 않습니다. 이미지 검증 오류와 저장소 오류와 CancellationError는 그대로 전파합니다.
struct ClipShareService: Sendable {
    private let storage: any ClipStorageService
    private let images: ClipImageService
    private let downloads: ClipImageDownloadService

    init(
        storage: any ClipStorageService,
        images: ClipImageService,
        downloads: ClipImageDownloadService
    ) {
        self.storage = storage
        self.images = images
        self.downloads = downloads
    }

    func save(_ item: ClipShareItem) async throws -> ClipShareSaveResult {
        let data: Data?
        do {
            data = try await Self.loadImageData(from: item)
        } catch {
            try Task.checkCancellation()
            return .loadFailed
        }
        guard let data else { return try await saveText(item) }
        // 저장이 시작된 뒤에는 취소를 다시 확인하지 않습니다.
        try Task.checkCancellation()
        let result = try await images.saveImage(data)
        return .saved(result.value)
    }

    private func saveText(_ item: ClipShareItem) async throws -> ClipShareSaveResult {
        let text: String?
        do {
            text = try await Self.loadText(from: item)
        } catch {
            try Task.checkCancellation()
            return .loadFailed
        }
        guard let text, ClipContent.text(text).isValid else { return .empty }
        if await Self.isURLOnly(item),
           let url = Self.imageURL(from: text),
           let result = try await saveDownloadedImage(from: url) {
            return result
        }
        // 저장이 시작된 뒤에는 취소를 다시 확인하지 않습니다.
        try Task.checkCancellation()
        let clip = Clip(content: .text(text), name: item.title)
        try await storage.insert(clip)
        return .saved(clip)
    }

    /// 내려받기나 이미지 검증에 실패하면 nil이며 텍스트 경로가 이어서 처리합니다.
    /// 저장소 오류는 전파하고 취소는 CancellationError로 전파합니다.
    private func saveDownloadedImage(from url: URL) async throws -> ClipShareSaveResult? {
        let data: Data
        do {
            data = try await downloads.loadImage(from: url)
        } catch {
            try Task.checkCancellation()
            return nil
        }
        // 저장이 시작된 뒤에는 취소를 다시 확인하지 않습니다.
        try Task.checkCancellation()
        do {
            let result = try await images.saveImage(data, memo: url.absoluteString)
            return .saved(result.value)
        } catch let error as ClipImageFileError where error == .invalidImage || error == .unsupportedImage {
            return nil
        }
    }

    /// 지원하는 첫 첨부가 이미지와 텍스트 형식 없이 URL 형식만 가지는지 확인합니다.
    @MainActor
    private static func isURLOnly(_ item: ClipShareItem) -> Bool {
        let textType = UTType.plainText.identifier
        let urlType = UTType.url.identifier
        guard let provider = item.providers.first(where: {
            $0.hasItemConformingToTypeIdentifier(textType) || $0.hasItemConformingToTypeIdentifier(urlType)
        }) else { return false }
        return provider.hasItemConformingToTypeIdentifier(urlType) && !provider.hasItemConformingToTypeIdentifier(textType)
    }

    /// 단일 http 또는 https URL이고 경로나 쿼리 값에 든 주소의 확장자가 이미지 형식일 때만 URL을 돌려줍니다.
    /// 네트워크 요청은 하지 않으며 돌려주는 URL은 쿼리를 포함한 원본 그대로입니다.
    private static func imageURL(from text: String) -> URL? {
        guard ClipContent.text(text).isWebLink, let url = URL(string: text) else { return nil }
        let queryURLs = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
            .compactMap { $0.value.flatMap { URL(string: $0) } } ?? []
        return ([url] + queryURLs).contains(where: hasImageExtension) ? url : nil
    }

    private static func hasImageExtension(_ url: URL) -> Bool {
        UTType(filenameExtension: url.pathExtension)?.conforms(to: .image) == true
    }

    /// 텍스트와 URL과 이미지 중 지원하는 첫 첨부만 확인합니다.
    /// 그 첨부가 이미지 형식을 가지면 URL이나 텍스트 형식이 함께 있어도 등록된 첫 이미지 형식의 원본 데이터를 읽습니다.
    /// 이미지 형식이 없으면 nil이며 텍스트 경로가 이어서 처리합니다.
    @MainActor
    private static func loadImageData(from item: ClipShareItem) async throws -> Data? {
        guard let provider = item.providers.first(where: {
            $0.hasItemConformingToTypeIdentifier(UTType.image.identifier)
                || $0.hasItemConformingToTypeIdentifier(UTType.plainText.identifier)
                || $0.hasItemConformingToTypeIdentifier(UTType.url.identifier)
        }),
            let typeIdentifier = provider.registeredTypeIdentifiers.first(where: {
                UTType($0)?.conforms(to: .image) == true
            }) else { return nil }
        return try await loadData(from: provider, typeIdentifier: typeIdentifier)
    }

    /// 작업을 취소하면 Progress를 취소해 느린 로드를 멈춥니다.
    /// 취소하면 NSItemProvider가 취소 오류로 완료 핸들러를 다시 호출할 수 있으므로 처음 호출만 사용해 continuation을 한 번만 재개합니다.
    @MainActor
    private static func loadData(
        from provider: NSItemProvider,
        typeIdentifier: String
    ) async throws -> Data {
        let progress = OSAllocatedUnfairLock<Progress?>(initialState: nil)
        let isResumed = OSAllocatedUnfairLock(initialState: false)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let loading = provider.loadDataRepresentation(forTypeIdentifier: typeIdentifier) { data, error in
                    let isFirst = isResumed.withLock { resumed in
                        defer { resumed = true }
                        return !resumed
                    }
                    guard isFirst else { return }
                    if let data {
                        continuation.resume(returning: data)
                    } else {
                        continuation.resume(throwing: error ?? CocoaError(.fileReadUnknown))
                    }
                }
                progress.withLock { $0 = loading }
                // Progress를 보관하기 전에 취소된 경우를 놓치지 않습니다.
                if Task.isCancelled { loading.cancel() }
            }
        } onCancel: {
            progress.withLock { $0 }?.cancel()
        }
    }

    /// 지원하는 첫 첨부만 읽습니다. 같은 첨부에서는 텍스트를 우선하고 공백뿐이면 URL로 대체합니다.
    /// 지원하는 첨부가 없으면 nil입니다. URL은 정규화하지 않고 원본 문자열을 그대로 사용합니다.
    @MainActor
    private static func loadText(from item: ClipShareItem) async throws -> String? {
        let textType = UTType.plainText.identifier
        let urlType = UTType.url.identifier
        guard let provider = item.providers.first(where: {
            $0.hasItemConformingToTypeIdentifier(textType) || $0.hasItemConformingToTypeIdentifier(urlType)
        }) else { return nil }
        let hasURL = provider.hasItemConformingToTypeIdentifier(urlType)
        if provider.hasItemConformingToTypeIdentifier(textType) {
            let text = try await load(from: provider, typeIdentifier: textType)
            if ClipContent.text(text).isValid || !hasURL { return text }
        }
        return try await load(from: provider, typeIdentifier: urlType)
    }

    /// 완료 핸들러에서만 continuation을 재개하므로 정확히 한 번 재개합니다.
    /// loadObject는 공유한 앱이 NSString을 객체로 등록한 경우 읽지 못하므로 등록된 항목을 그대로 돌려주는 loadItem을 사용합니다.
    @MainActor
    private static func load(
        from provider: NSItemProvider,
        typeIdentifier: String
    ) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { item, error in
                if let text = string(from: item, typeIdentifier: typeIdentifier) {
                    continuation.resume(returning: text)
                } else {
                    continuation.resume(throwing: error ?? CocoaError(.fileReadUnknown))
                }
            }
        }
    }

    /// 항목의 실제 형식에 맞춰 문자열로 바꿉니다. 지원하지 않는 형식은 nil입니다.
    private nonisolated static func string(
        from item: (any NSSecureCoding)?,
        typeIdentifier: String
    ) -> String? {
        switch item {
        case let text as String:
            text
        case let url as URL:
            url.absoluteString
        case let data as Data:
            urlString(from: data, typeIdentifier: typeIdentifier) ?? String(data: data, encoding: .utf8)
        case let attributed as NSAttributedString:
            attributed.string
        default:
            nil
        }
    }

    /// NSURL이 제공한 URL 데이터는 UTF-8 문자열이 아닐 수 있습니다. 따라서 NSURL의 해석을 먼저 사용합니다.
    private nonisolated static func urlString(
        from data: Data,
        typeIdentifier: String
    ) -> String? {
        guard UTType(typeIdentifier)?.conforms(to: .url) == true else { return nil }
        return (try? NSURL.object(withItemProviderData: data, typeIdentifier: typeIdentifier))?.absoluteString
    }
}
