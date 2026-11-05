//
//  ClipCoreFoundationTests.swift
//  PlystTests
//
//  Created by opfic on 11/6/26.
//

import Foundation
import XCTest
@testable import Plyst

/// 코어 판정을 실행 중인 OS의 Foundation 결과와 직접 비교
/// isValid가 달라지면 저장된 클립을 읽지 못해 홈 전체가 열리지 않으므로 모든 스칼라를 비교
/// isWebLink는 IDNA를 재현하지 않아 ASCII 입력만 비교
final class ClipCoreFoundationTests: XCTestCase {
    func testValidityMatchesFoundationForEveryScalar() {
        for value in UInt32(0)...0x10FFFF {
            guard let scalar = UnicodeScalar(value) else { continue }
            let text = String(Character(scalar))
            XCTAssertEqual(ClipContent.text(text).isValid, foundationIsValid(text), "U+\(String(value, radix: 16))")
        }
    }

    func testWebLinkMatchesFoundationForEveryASCIICharacterInEachURLPart() {
        let templates = [
            "https://u@@v@example.com/",
            "https://ex@@ample.com/",
            "https://example.com:8@@0/",
            "https://example.com/a@@b",
            "https://example.com/?a@@b",
            "https://example.com/#a@@b",
            "https://[a@@b]/",
            "https://@@/",
            "https://@@a/",
            "https://a@@/",
            "@@https://a/"
        ]
        for value in UInt8(0)..<128 {
            let character = String(UnicodeScalar(value))
            for template in templates {
                let text = template.replacingOccurrences(of: "@@", with: character)
                XCTAssertEqual(ClipContent.text(text).isWebLink, foundationIsWebLink(text), text.debugDescription)
            }
        }
    }

    func testWebLinkMatchesFoundationForURLShapedASCIIText() {
        let schemes = ["https://", "http://", "HTTP://", "https:", "https:/", "https:///", "ftp://", ""]
        let users = ["", "u@", "u:p@", "@", "u@v@", ":@"]
        let hosts = ["a", "example.com", "exa_mple.com", "a..b", "1.2.3.4", "[::1]", "[zz]", "", "a-b.c", "%41", "%zz"]
        let ports = ["", ":", ":80", ":8a", ":99999"]
        let paths = ["", "/", "/a", "/a|b", "/%zz", "/a b", "?x", "#y", "/?a=b#c", "\\", "/\\"]

        for scheme in schemes {
            for user in users {
                for host in hosts {
                    for port in ports {
                        for path in paths {
                            let text = scheme + user + host + port + path
                            XCTAssertEqual(ClipContent.text(text).isWebLink, foundationIsWebLink(text), text.debugDescription)
                        }
                    }
                }
            }
        }
    }

    private func foundationIsValid(_ text: String) -> Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func foundationIsWebLink(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
              let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = url.host(),
              !host.isEmpty else { return false }
        return true
    }
}
