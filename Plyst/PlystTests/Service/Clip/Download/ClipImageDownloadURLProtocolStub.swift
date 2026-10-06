//
//  ClipImageDownloadURLProtocolStub.swift
//  PlystTests
//
//  Created by opfic on 10/3/26.
//

import Foundation
import os
@testable import Plyst

/// 네트워크 없이 `ClipImageDownloadService`의 세션 응답을 대신하는 URLProtocol입니다.
/// 상태는 정적이므로 테스트마다 `reset(_:)`으로 초기화합니다.
final class ClipImageDownloadURLProtocolStub: URLProtocol, @unchecked Sendable {
    enum Behavior: Sendable {
        case response(
            statusCode: Int,
            headers: [String: String],
            body: Data
        )
        case failure(URLError.Code)
        /// 응답하지 않고 대기합니다. 취소로 전송이 중단되는지 확인할 때 사용합니다.
        case stall
    }

    private struct State {
        var behavior = Behavior.stall
        var requests = [URL]()
        var stopCount = 0
    }

    private static let state = OSAllocatedUnfairLock(initialState: State())

    static var requests: [URL] {
        state.withLock { $0.requests }
    }

    static var stopCount: Int {
        state.withLock { $0.stopCount }
    }

    static func reset(_ behavior: Behavior) {
        state.withLock { $0 = State(behavior: behavior) }
    }

    /// 앱이 쓰는 구성에 이 스텁만 더한 세션입니다.
    static func makeSession() -> URLSession {
        let configuration = ClipImageDownloadService.configuration
        configuration.protocolClasses = [ClipImageDownloadURLProtocolStub.self]
        return URLSession(configuration: configuration)
    }

    override static func canInit(with request: URLRequest) -> Bool {
        true
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url else { return }
        let behavior = Self.state.withLock { state in
            state.requests.append(url)
            return state.behavior
        }
        switch behavior {
        case .response(let statusCode, let headers, let body):
            guard let response = HTTPURLResponse(
                url: url,
                statusCode: statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: headers
            ) else { return }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        case .failure(let code):
            client?.urlProtocol(self, didFailWithError: URLError(code))
        case .stall:
            break
        }
    }

    override func stopLoading() {
        Self.state.withLock { $0.stopCount += 1 }
    }
}
