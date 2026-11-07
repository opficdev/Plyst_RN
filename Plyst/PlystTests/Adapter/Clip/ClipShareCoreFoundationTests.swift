//
//  ClipShareCoreFoundationTests.swift
//  PlystTests
//
//  Created by opfic on 11/7/26.
//

import Foundation
import os
import PlystCore
import UniformTypeIdentifiers
import XCTest
@testable import Plyst

/// 공유 텍스트의 이미지 주소 판정과 요청 문자열을 실행 중인 OS의 Foundation 결과와 직접 비교
/// 판정 함수를 공개하지 않으므로 ClipCoreAdapter와 받은 주소를 기록하는 내려받기 대역을 거침
/// 비ASCII 호스트는 IDNA를 재현하지 않아 비교하지 않음
/// 확장자 표는 고정한 iOS 판정이므로 OS와 비교하지 않음
final class ClipShareCoreFoundationTests: ClipTemporaryDirectoryTestCase {
    func testImageURLMatchesFoundationForEveryASCIICharacterInEachURLPart() async throws {
        let core = try makeCore()
        let templates = [
            "https://u@@v@example.com/a.png",
            "https://example.com/a@@b.png",
            "https://example.com/@@.png",
            "https://example.com/a.p@@ng",
            "https://example.com/a.png@@",
            "https://example.com/a.png/@@",
            "https://example.com/p?q=@@&u=a.png",
            "https://example.com/p?u=a@@b.png",
            "https://example.com/p?u=@@b.png",
            "https://example.com/p?u@@a.png",
            "https://example.com/a.png#@@",
            "https://example.com/p#a@@b.png"
        ]
        for value in UInt8(0)..<128 {
            let character = String(UnicodeScalar(value))
            for template in templates {
                let text = template.replacingOccurrences(of: "@@", with: character)
                let requested = try await requestedURL(for: text, core: core)
                XCTAssertEqual(requested, foundationImageURL(text), text.debugDescription)
            }
        }
    }

    func testRequestStringMatchesFoundationForNonASCIIParts() async throws {
        let core = try makeCore()
        let texts = [
            "https://example.com/한글.png",
            "https://example.com/café/😀.png?q=é#조각",
            "https://사용자@example.com/a.png",
            "https://example.com/a.png?q=%ED%95%9C%EA%B8%80",
            "https://example.com/p?u=https%3A%2F%2Fa.com%2F%EC%82%AC%EC%A7%84.png"
        ]
        for text in texts {
            let requested = try await requestedURL(for: text, core: core)
            XCTAssertEqual(requested, foundationImageURL(text), text)
        }
    }

    private func requestedURL(
        for text: String,
        core: ClipCoreAdapter
    ) async throws -> String? {
        let downloader = RecordedDownloader()
        _ = try await core.saveSharedText(
            text,
            title: nil,
            allowsDownload: true,
            downloader: downloader
        )
        return downloader.urls.first
    }

    /// 코어로 옮기기 전 ClipShareService의 판정
    private func foundationImageURL(_ text: String) -> String? {
        guard ClipContent.text(text).isWebLink, let url = URL(string: text) else { return nil }
        let queryURLs = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
            .compactMap { $0.value.flatMap { URL(string: $0) } } ?? []
        let isImage = ([url] + queryURLs).contains {
            UTType(filenameExtension: $0.pathExtension)?.conforms(to: .image) == true
        }
        return isImage ? url.absoluteString : nil
    }
}

/// 받은 주소를 기록하고 내려받기에 실패하는 대역
private final class RecordedDownloader: ClipImageDownloader {
    private let recorded = OSAllocatedUnfairLock<[String]>(initialState: [])

    var urls: [String] { recorded.withLock { $0 } }

    func download(
        url: String,
        path: String,
        cancellation: any ClipCancellationSource
    ) throws -> String? {
        recorded.withLock { $0.append(url) }
        throw ClipDownloadError.Failed
    }
}
