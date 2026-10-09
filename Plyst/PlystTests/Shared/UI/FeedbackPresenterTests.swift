//
//  FeedbackPresenterTests.swift
//  PlystTests
//
//  Created by opfic on 10/4/26.
//

import Foundation
import XCTest
@testable import Plyst

@MainActor
final class FeedbackPresenterTests: XCTestCase {
    func test_같은_식별자는_한_번만_표시를_요청한다() {
        var messages = [String]()
        let presenter = FeedbackPresenter(
            show: { message, _ in messages.append(message) },
            dismiss: { _ in }
        )
        let feedback = FeedbackTestValue(message: "첫 표시")
        presenter.update(feedback)

        presenter.update(FeedbackTestValue(id: feedback.id, message: "중복 표시"))
        presenter.update(nil)
        presenter.update(feedback)

        XCTAssertEqual(messages, ["첫 표시"])
    }

    func test_메시지와_성공_여부를_표시_요청에_전달한다() {
        var requests = [(message: String, isSuccess: Bool)]()
        let presenter = FeedbackPresenter(
            show: { requests.append((message: $0, isSuccess: $1)) },
            dismiss: { _ in }
        )
        presenter.update(FeedbackTestValue(message: "성공"))

        presenter.update(FeedbackTestValue(message: "실패", isSuccess: false))

        XCTAssertEqual(requests.map(\.message), ["성공", "실패"])
        XCTAssertEqual(requests.map(\.isSuccess), [true, false])
    }

    func test_표시_시간이_지나면_원래_식별자로_피드백을_닫는다() async {
        let dismissed = expectation(description: "표시 시간이 지나면 원래 식별자로 닫습니다")
        let feedback = FeedbackTestValue(message: "자동 닫기")
        let presenter = FeedbackPresenter(
            show: { _, _ in },
            duration: .milliseconds(10),
            dismiss: {
                XCTAssertEqual($0, feedback.id)
                dismissed.fulfill()
            }
        )
        presenter.update(feedback)

        await fulfillment(of: [dismissed], timeout: 1)
    }

    func test_새_피드백을_표시하고_이전_타이머를_취소한다() async {
        let dismissed = expectation(description: "마지막 피드백만 닫기를 알립니다")
        let feedback = FeedbackTestValue(message: "새 토스트")
        var messages = [String]()
        var ids = [UUID]()
        let presenter = FeedbackPresenter(
            show: { message, _ in messages.append(message) },
            duration: .milliseconds(10),
            dismiss: {
                ids.append($0)
                dismissed.fulfill()
            }
        )
        presenter.update(FeedbackTestValue(message: "이전 토스트"))
        presenter.update(feedback)
        XCTAssertEqual(messages, ["이전 토스트", "새 토스트"])

        await fulfillment(of: [dismissed], timeout: 1)

        XCTAssertEqual(ids, [feedback.id])
    }

    func test_presenter가_해제돼도_피드백을_닫는다() async {
        let dismissed = expectation(description: "화면이 해제돼도 피드백 상태를 비우도록 알립니다")
        let feedback = FeedbackTestValue(message: "화면 해제 후 닫기")
        var presenter = Optional(FeedbackPresenter(
            show: { _, _ in },
            duration: .milliseconds(10),
            dismiss: {
                XCTAssertEqual($0, feedback.id)
                dismissed.fulfill()
            }
        ))
        weak var weakPresenter = presenter
        presenter?.update(feedback)

        presenter = nil

        XCTAssertNil(weakPresenter)
        await fulfillment(of: [dismissed], timeout: 1)
    }
}

private struct FeedbackTestValue: FeedbackPresentable {
    let id: UUID
    let message: String
    let isSuccess: Bool

    init(
        id: UUID = UUID(),
        message: String,
        isSuccess: Bool = true
    ) {
        self.id = id
        self.message = message
        self.isSuccess = isSuccess
    }
}
