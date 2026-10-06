//
//  ClipImageDownloadServiceTests.swift
//  PlystTests
//
//  Created by opfic on 10/3/26.
//

import Foundation
import XCTest
@testable import Plyst

final class ClipImageDownloadServiceTests: XCTestCase {
    private let maximumByteCount = 20 * 1024 * 1024
    private let imageURL = URL(string: "https://example.com/photo.png")!

    func testSuccessReturnsBodyWithSingleRequest() async throws {
        let body = Data([1, 2, 3, 4])
        stub(body: body)

        let data = try await makeService().loadImage(from: imageURL)

        XCTAssertEqual(data, body)
        XCTAssertEqual(ClipImageDownloadURLProtocolStub.requests, [imageURL])
    }

    func testBodyExactlyAtLimitSucceeds() async throws {
        let body = Data(count: maximumByteCount)
        stub(body: body)

        let data = try await makeService().loadImage(from: imageURL)

        XCTAssertEqual(data.count, maximumByteCount)
    }

    func testNonSuccessStatusThrowsInvalidResponse() async {
        stub(statusCode: 404)

        await assertThrows(.invalidResponse)
    }

    func testNonImageContentTypeThrowsNotImage() async {
        stub(mimeType: "text/html")

        await assertThrows(.notImage)
    }

    func testOctetStreamContentTypeThrowsNotImage() async {
        stub(mimeType: "application/octet-stream")

        await assertThrows(.notImage)
    }

    func testDeclaredLengthOverLimitThrowsTooLarge() async {
        stub(headers: ["Content-Length": "\(maximumByteCount + 1)"])

        await assertThrows(.tooLarge)
    }

    func testBodyOverLimitWithoutDeclaredLengthThrowsTooLarge() async {
        stub(body: Data(count: maximumByteCount + 1))

        await assertThrows(.tooLarge)
    }

    func testUnsupportedSchemeThrowsWithoutRequest() async throws {
        stub()
        let url = try XCTUnwrap(URL(string: "ftp://example.com/photo.png"))

        await assertThrows(.unsupportedURL, url: url)

        XCTAssertTrue(ClipImageDownloadURLProtocolStub.requests.isEmpty)
    }

    func testTransportFailureThrowsRequestFailed() async {
        ClipImageDownloadURLProtocolStub.reset(.failure(.notConnectedToInternet))

        await assertThrows(.requestFailed)
    }

    func testCancellationThrowsCancellationErrorAndStopsLoading() async throws {
        ClipImageDownloadURLProtocolStub.reset(.stall)
        let service = makeService()
        let url = imageURL
        let task = Task { try await service.loadImage(from: url) }
        try await wait { !ClipImageDownloadURLProtocolStub.requests.isEmpty }

        task.cancel()

        do {
            _ = try await task.value
            XCTFail("취소 오류 누락")
        } catch is CancellationError {
            try await wait { 0 < ClipImageDownloadURLProtocolStub.stopCount }
        } catch {
            XCTFail("취소가 아닌 오류: \(error)")
        }
    }

    private func makeService() -> ClipImageDownloadService {
        let session = ClipImageDownloadURLProtocolStub.makeSession()
        addTeardownBlock { session.invalidateAndCancel() }
        return ClipImageDownloadService(session: session)
    }

    private func stub(
        statusCode: Int = 200,
        mimeType: String = "image/png",
        headers: [String: String] = [:],
        body: Data = Data([1])
    ) {
        ClipImageDownloadURLProtocolStub.reset(.response(
            statusCode: statusCode,
            headers: headers.merging(["Content-Type": mimeType]) { $1 },
            body: body
        ))
    }

    private func assertThrows(
        _ expected: ClipImageDownloadError,
        url: URL? = nil
    ) async {
        do {
            _ = try await makeService().loadImage(from: url ?? imageURL)
            XCTFail("오류 누락")
        } catch {
            XCTAssertEqual(error as? ClipImageDownloadError, expected)
        }
    }

    private func wait(until condition: @escaping () -> Bool) async throws {
        for _ in 0..<500 where !condition() {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(condition())
    }
}
