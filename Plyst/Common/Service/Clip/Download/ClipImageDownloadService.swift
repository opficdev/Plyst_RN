//
//  ClipImageDownloadService.swift
//  Plyst
//
//  Created by opfic on 10/3/26.
//

import Foundation
import UniformTypeIdentifiers

/// 이미지 URL의 응답 본문을 최대 바이트 수 안에서 메모리로 내려받습니다.
///
/// 세션의 수명은 호출하는 쪽이 소유합니다. 이 서비스는 세션을 만들거나 무효화하지 않습니다.
/// 요청은 GET 하나이며 쿠키와 캐시를 쓰지 않는 `configuration`으로 만든 세션을 받는 것을 전제로 합니다.
/// 응답이 2xx이고 `Content-Type`이 이미지일 때만 본문을 읽으며 검증과 저장은 하지 않습니다.
/// 작업을 취소하면 전송을 중단하고 CancellationError를 전파합니다.
struct ClipImageDownloadService: Sendable {
    /// 내려받을 수 있는 본문의 최대 바이트 수입니다.
    private static let maximumByteCount = 20 * 1024 * 1024

    private let session: URLSession

    /// 쿠키와 캐시를 쓰지 않고 요청 시간과 전체 시간을 제한하는 세션 구성입니다.
    static var configuration: URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.waitsForConnectivity = false
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 20
        return configuration
    }

    init(session: URLSession) {
        self.session = session
    }

    func loadImage(from url: URL) async throws -> Data {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            throw ClipImageDownloadError.unsupportedURL
        }
        do {
            let (bytes, response) = try await session.bytes(from: url)
            // 일찍 끝나는 경우에도 남은 전송을 중단합니다.
            defer { bytes.task.cancel() }
            guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else {
                throw ClipImageDownloadError.invalidResponse
            }
            guard let mimeType = response.mimeType, UTType(mimeType: mimeType)?.conforms(to: .image) == true else {
                throw ClipImageDownloadError.notImage
            }
            guard response.expectedContentLength <= Int64(Self.maximumByteCount) else {
                throw ClipImageDownloadError.tooLarge
            }
            var data = Data()
            for try await byte in bytes {
                // 최대치를 넘는 바이트는 보관하지 않습니다.
                guard data.count < Self.maximumByteCount else { throw ClipImageDownloadError.tooLarge }
                data.append(byte)
            }
            return data
        } catch let error as ClipImageDownloadError {
            throw error
        } catch {
            try Task.checkCancellation()
            throw ClipImageDownloadError.requestFailed
        }
    }
}
