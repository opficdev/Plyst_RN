//
//  ClipShareService.swift
//  Plyst
//
//  Created by opfic on 10/1/26.
//

import Foundation
import os
import UniformTypeIdentifiers

/// 공유 시트로 받은 항목을 클립으로 저장
/// 여러 항목은 다루지 않음
///
/// 지원하는 첫 첨부가 이미지 형식을 가지면 변환 없이 원본 바이트를 이름 없는 이미지 클립으로 저장
/// 그 외에는 텍스트나 URL을 코어에 넘겨 저장
/// 지원하는 첫 첨부가 URL 하나뿐일 때만 코어가 이미지 주소를 내려받도록 허용
/// 이미지 주소 판정, 내려받기 순서, 실패 시 텍스트 저장, 제목 정리는 코어가 결정
/// 저장을 시도할 때마다 첨부를 다시 읽으므로 읽기 실패 후에도 같은 항목으로 다시 시도할 수 있음
/// 읽기에 실패하면 저장소에 쓰지 않음
/// 이미지 검증 오류와 저장소 오류와 CancellationError는 그대로 전파
struct ClipShareService: Sendable {
    private let core: ClipCoreAdapter
    private let downloader: SystemClipImageDownloader

    init(
        core: ClipCoreAdapter,
        downloader: SystemClipImageDownloader
    ) {
        self.core = core
        self.downloader = downloader
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
        // 저장이 시작된 뒤에는 취소를 다시 확인하지 않음
        try Task.checkCancellation()
        let result = try await core.saveImage(data)
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
        guard let text else { return .empty }
        let clip = try await core.saveSharedText(
            text,
            title: item.title,
            allowsDownload: await Self.isURLOnly(item),
            downloader: downloader
        )
        return clip.map(ClipShareSaveResult.saved) ?? .empty
    }

    /// 지원하는 첫 첨부가 이미지와 텍스트 형식 없이 URL 형식만 가지는지 확인
    @MainActor
    private static func isURLOnly(_ item: ClipShareItem) -> Bool {
        let textType = UTType.plainText.identifier
        let urlType = UTType.url.identifier
        guard let provider = item.providers.first(where: {
            $0.hasItemConformingToTypeIdentifier(textType) || $0.hasItemConformingToTypeIdentifier(urlType)
        }) else { return false }
        return provider.hasItemConformingToTypeIdentifier(urlType) && !provider.hasItemConformingToTypeIdentifier(textType)
    }

    /// 텍스트와 URL과 이미지 중 지원하는 첫 첨부만 확인
    /// 그 첨부가 이미지 형식을 가지면 URL이나 텍스트 형식이 함께 있어도 등록된 첫 이미지 형식의 원본 데이터를 읽음
    /// 이미지 형식이 없으면 nil이며 텍스트 경로가 이어서 처리
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

    /// 작업을 취소하면 Progress를 취소해 느린 로드를 멈춤
    /// 취소하면 NSItemProvider가 취소 오류로 완료 핸들러를 다시 호출할 수 있으므로 처음 호출만 사용해 continuation을 한 번만 재개
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
                // Progress를 보관하기 전에 취소된 경우를 놓치지 않음
                if Task.isCancelled { loading.cancel() }
            }
        } onCancel: {
            progress.withLock { $0 }?.cancel()
        }
    }

    /// 지원하는 첫 첨부만 읽음
    /// 같은 첨부에서는 텍스트를 우선하고 공백뿐이면 URL로 대체
    /// 지원하는 첨부가 없으면 nil
    /// URL은 정규화하지 않고 원본 문자열을 그대로 사용
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

    /// 완료 핸들러에서만 continuation을 재개하므로 정확히 한 번 재개
    /// loadObject는 공유한 앱이 NSString을 객체로 등록한 경우 읽지 못하므로 등록된 항목을 그대로 돌려주는 loadItem을 사용
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

    /// 항목의 실제 형식에 맞춰 문자열로 바꿈
    /// 지원하지 않는 형식은 nil
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

    /// NSURL이 제공한 URL 데이터는 UTF-8 문자열이 아닐 수 있음
    /// 따라서 NSURL의 해석을 먼저 사용
    private nonisolated static func urlString(
        from data: Data,
        typeIdentifier: String
    ) -> String? {
        guard UTType(typeIdentifier)?.conforms(to: .url) == true else { return nil }
        return (try? NSURL.object(withItemProviderData: data, typeIdentifier: typeIdentifier))?.absoluteString
    }
}
