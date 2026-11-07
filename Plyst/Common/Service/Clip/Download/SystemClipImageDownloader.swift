//
//  SystemClipImageDownloader.swift
//  Plyst
//
//  Created by opfic on 10/3/26.
//

import Foundation
import os
import PlystCore

/// 코어가 정한 경로에 이미지 URL의 응답 본문을 최대 바이트 수 안에서 내려받음
///
/// 세션의 수명은 호출하는 쪽이 소유
/// 이 구현은 세션을 만들거나 무효화하지 않음
/// 요청은 GET 하나이며 쿠키와 캐시를 쓰지 않는 `configuration`으로 만든 세션을 받는 것을 전제로 함
/// 응답이 2xx일 때만 본문을 쓰고 응답 형식 판정과 검증과 저장은 코어가 맡음
/// 코어의 공유 줄에서 동기로 불리며 전송이 끝날 때까지 그 줄을 막고 기다림
/// 기다리는 동안 취소 상태를 읽어 전송을 끊음
final class SystemClipImageDownloader: ClipImageDownloader {
    /// 내려받을 수 있는 본문의 최대 바이트 수
    private static let maximumByteCount = 20 * 1024 * 1024
    /// 파일에 한 번에 쓰는 바이트 수
    private static let bufferByteCount = 64 * 1024
    /// 기다리는 동안 취소 상태를 읽는 간격
    private static let cancellationInterval = DispatchTimeInterval.milliseconds(100)

    private let session: URLSession

    /// 쿠키와 캐시를 쓰지 않고 요청 시간과 전체 시간을 제한하는 세션 구성
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

    /// Content-Type 헤더 원문을 돌려줌
    /// 전송은 협력 스레드의 Task가 맡고 이 호출은 코어가 준 전용 스레드에서 끝까지 기다림
    func download(
        url: String,
        path: String,
        cancellation: any ClipCancellationSource
    ) throws -> String? {
        guard let target = URL(string: url), let scheme = target.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            throw ClipDownloadError.Failed
        }
        let outcome = OSAllocatedUnfairLock<Result<String?, ClipDownloadError>>(initialState: .failure(.Failed))
        let finished = DispatchSemaphore(value: 0)
        let task = Task { [session] in
            let result = await Self.transfer(target, to: path, session: session)
            outcome.withLock { $0 = result }
            finished.signal()
        }
        // 전송 Task가 파일을 닫을 때까지 기다린 뒤 돌아감
        while finished.wait(timeout: .now() + Self.cancellationInterval) == .timedOut {
            if cancellation.isCancelled() { task.cancel() }
        }
        return try outcome.withLock { $0 }.get()
    }

    private static func transfer(
        _ url: URL,
        to path: String,
        session: URLSession
    ) async -> Result<String?, ClipDownloadError> {
        do {
            let (bytes, response) = try await session.bytes(from: url)
            // 일찍 끝나는 경우에도 남은 전송을 중단
            defer { bytes.task.cancel() }
            guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode),
                  response.expectedContentLength <= Int64(maximumByteCount) else {
                return .failure(.Failed)
            }
            // 이미 있는 항목과 링크를 따라가지 않고 새 파일만 만듦
            let descriptor = open(path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
            guard 0 <= descriptor else { return .failure(.Failed) }
            let file = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
            var buffer = Data(capacity: bufferByteCount)
            var byteCount = 0
            for try await byte in bytes {
                byteCount += 1
                // 최대치를 넘는 바이트는 보관하지 않음
                guard byteCount <= maximumByteCount else { return .failure(.Failed) }
                buffer.append(byte)
                if buffer.count == bufferByteCount {
                    try file.write(contentsOf: buffer)
                    buffer.removeAll(keepingCapacity: true)
                }
            }
            try file.write(contentsOf: buffer)
            try file.close()
            return .success(response.value(forHTTPHeaderField: "Content-Type"))
        } catch {
            return .failure(Task.isCancelled ? .Cancelled : .Failed)
        }
    }
}
