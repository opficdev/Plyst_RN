//
//  ClipSearchCoreFoundationTests.swift
//  PlystTests
//
//  Created by opfic on 11/6/26.
//

import Foundation
import XCTest
@testable import Plyst

/// 코어의 최근 검색어 판정을 실행 중인 OS의 Foundation 결과와 직접 비교
/// 같은 항목 판정이 넓어지면 저장된 기록을 읽지 못하므로 대소문자 변환이 있는 모든 스칼라를 비교
/// 하기 이오타와 결합 표시가 섞인 조합은 Foundation과 일부러 다르므로 비교하지 않음
final class ClipSearchCoreFoundationTests: XCTestCase {
    func testQueryMatchesFoundationForEveryScalar() {
        for value in UInt32(0)...0x10FFFF {
            guard let scalar = UnicodeScalar(value) else { continue }
            let text = String(Character(scalar))
            let name = "U+\(String(value, radix: 16))"
            XCTAssertEqual(try ClipSearchQuery(text)?.text, foundationQuery(text), name)
            XCTAssertEqual(try ClipSearchQuery(text + "a")?.text, foundationQuery(text + "a"), name)
        }
    }

    func testSameTermMatchesFoundationForEveryCaseMappedScalar() {
        for value in UInt32(0)...0x10FFFF {
            guard let scalar = UnicodeScalar(value) else { continue }
            let text = String(Character(scalar))
            guard foundationQuery(text) == text else { continue }
            for other in [text.lowercased(), text.uppercased()] where other != text {
                XCTAssertEqual(try isSame(text, other), foundationIsSame(text, other), "U+\(String(value, radix: 16))")
            }
        }
    }

    func testSameTermMatchesFoundationForRepresentativePairs() {
        let pairs = [
            ("한글", "한글".decomposedStringWithCanonicalMapping),
            ("ß", "SS"),
            ("ẞ", "ß"),
            ("ﬁ", "FI"),
            ("İ", "i"),
            ("I", "ı"),
            ("ς", "Σ"),
            ("a\u{0323}\u{0307}", "a\u{0307}\u{0323}"),
            ("a\u{200B}b", "ab"),
            ("か", "カ")
        ]
        for (lhs, rhs) in pairs {
            XCTAssertEqual(try isSame(lhs, rhs), foundationIsSame(lhs, rhs), "\(lhs) \(rhs)")
        }
    }

    /// 같은 항목이 있는 목록은 복원 규칙을 통과하지 못함
    private func isSame(
        _ lhs: String,
        _ rhs: String
    ) throws -> Bool {
        try ClipSearchHistory(terms: [lhs, rhs]) == nil
    }

    private func foundationQuery(_ raw: String) -> String? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    private func foundationIsSame(
        _ lhs: String,
        _ rhs: String
    ) -> Bool {
        lhs.compare(rhs, options: .caseInsensitive) == .orderedSame
    }
}
