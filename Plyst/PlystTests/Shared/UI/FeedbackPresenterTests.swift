//
//  FeedbackPresenterTests.swift
//  PlystTests
//
//  Created by opfic on 10/4/26.
//

import UIKit
import XCTest
@testable import Plyst

@MainActor
final class FeedbackPresenterTests: XCTestCase {
    func testSameIDIsShownOnce() throws {
        let window = try makeWindow()
        defer { window.hide() }
        let presenter = FeedbackPresenter(window: window, dismiss: { _ in })
        let feedback = FeedbackTestValue(message: "첫 표시")
        presenter.update(feedback)
        let toast = try findToast(in: window)

        presenter.update(FeedbackTestValue(id: feedback.id, message: "중복 표시"))

        XCTAssertEqual(toast.label.text, "첫 표시")
        XCTAssertEqual(window.subviews.compactMap { $0 as? ToastView }.count, 1)
    }

    func testSuccessAndFailureUseExistingColors() throws {
        let window = try makeWindow()
        defer { window.hide() }
        let presenter = FeedbackPresenter(window: window, dismiss: { _ in })
        presenter.update(FeedbackTestValue(message: "성공"))
        let toast = try findToast(in: window)
        XCTAssertEqual(toast.backgroundColor, UIColor(resource: .homeFeedbackSuccess))

        presenter.update(FeedbackTestValue(message: "실패", isSuccess: false))

        XCTAssertEqual(toast.label.text, "실패")
        XCTAssertEqual(toast.backgroundColor, UIColor(resource: .homeFeedbackFailure))
    }

    func testToastAutomaticallyHidesAndDismissesOriginalID() async throws {
        let window = try makeWindow()
        defer { window.hide() }
        let dismissed = expectation(description: "표시 시간이 지나면 원래 식별자로 닫습니다")
        let feedback = FeedbackTestValue(message: "자동 숨김")
        let presenter = FeedbackPresenter(
            window: window,
            duration: .milliseconds(10),
            dismiss: {
                XCTAssertEqual($0, feedback.id)
                dismissed.fulfill()
            }
        )
        presenter.update(feedback)
        let toast = try findToast(in: window)

        await fulfillment(of: [dismissed], timeout: 1)

        XCTAssertTrue(toast.isHidden || toast.alpha == 0)
    }

    func testEarlierPresenterCannotHideLaterToast() async throws {
        let window = try makeWindow()
        defer { window.hide() }
        let firstDismissed = expectation(description: "이전 토스트의 시간이 끝납니다")
        let secondDismissed = expectation(description: "나중 토스트의 시간이 끝납니다")
        let first = FeedbackPresenter(
            window: window,
            duration: .milliseconds(10),
            dismiss: { _ in firstDismissed.fulfill() }
        )
        let second = FeedbackPresenter(
            window: window,
            duration: .milliseconds(200),
            dismiss: { _ in secondDismissed.fulfill() }
        )
        let feedback = FeedbackTestValue(message: "이전 토스트")
        first.update(feedback)
        second.update(FeedbackTestValue(message: "나중 토스트"))
        let toast = try findToast(in: window)

        await fulfillment(of: [firstDismissed], timeout: 1)
        first.update(nil)
        first.update(feedback)

        XCTAssertEqual(toast.label.text, "나중 토스트")
        XCTAssertFalse(toast.isHidden)
        XCTAssertEqual(toast.alpha, 1)
        await fulfillment(of: [secondDismissed], timeout: 1)
        XCTAssertTrue(toast.isHidden || toast.alpha == 0)
    }

    func testPresenterThatNeverShowedCannotHideAnotherToast() throws {
        let window = try makeWindow()
        defer { window.hide() }
        let first = FeedbackPresenter(window: window, dismiss: { _ in })
        let second = FeedbackPresenter(window: window, dismiss: { _ in })
        first.update(FeedbackTestValue(message: "표시 중"))

        second.update(nil)

        let toast = try findToast(in: window)
        XCTAssertEqual(toast.label.text, "표시 중")
        XCTAssertFalse(toast.isHidden)
        XCTAssertEqual(toast.alpha, 1)
    }

    func testSamePresenterReplacesToastAndCancelsEarlierTimer() async throws {
        let window = try makeWindow()
        defer { window.hide() }
        let dismissed = expectation(description: "마지막 피드백만 닫기를 알립니다")
        let feedback = FeedbackTestValue(message: "새 토스트")
        var ids = [UUID]()
        let presenter = FeedbackPresenter(
            window: window,
            duration: .milliseconds(10),
            dismiss: {
                ids.append($0)
                dismissed.fulfill()
            }
        )
        presenter.update(FeedbackTestValue(message: "이전 토스트"))
        presenter.update(feedback)
        XCTAssertEqual(try findToast(in: window).label.text, "새 토스트")

        await fulfillment(of: [dismissed], timeout: 1)

        XCTAssertEqual(ids, [feedback.id])
    }

    func testToastDismissesAfterPresenterIsReleased() async throws {
        let window = try makeWindow()
        defer { window.hide() }
        let dismissed = expectation(description: "화면이 해제돼도 토스트를 닫습니다")
        let feedback = FeedbackTestValue(message: "화면 해제 후 숨김")
        var presenter = Optional(FeedbackPresenter(
            window: window,
            duration: .milliseconds(10),
            dismiss: {
                XCTAssertEqual($0, feedback.id)
                dismissed.fulfill()
            }
        ))
        weak var weakPresenter = presenter
        presenter?.update(feedback)
        let toast = try findToast(in: window)

        presenter = nil

        XCTAssertNil(weakPresenter)
        XCTAssertFalse(toast.isHidden)
        await fulfillment(of: [dismissed], timeout: 1)
        XCTAssertTrue(toast.isHidden || toast.alpha == 0)
    }

    func testToastRemainsInSameSceneWindowAcrossTransitionsAndModalPresentation() throws {
        let window = try makeWindow()
        let scene = try XCTUnwrap(window.windowScene)
        let main = UIWindow(windowScene: scene)
        let home = UIViewController()
        main.rootViewController = home
        main.isHidden = false
        defer {
            main.isHidden = true
            window.hide()
        }
        let presenter = FeedbackPresenter(window: window, dismiss: { _ in })
        presenter.update(FeedbackTestValue(message: "전환 중 표시"))
        let toast = try findToast(in: window)
        let search = UIViewController()

        home.addChild(search)
        home.view.addSubview(search.view)
        search.didMove(toParent: home)
        XCTAssertTrue(toast.window === window)
        search.present(UIViewController(), animated: false)
        XCTAssertTrue(toast.window === window)
        XCTAssertFalse(toast.isHidden)
        search.dismiss(animated: false)
        search.willMove(toParent: nil)
        search.view.removeFromSuperview()
        search.removeFromParent()
        main.rootViewController = UIViewController()

        XCTAssertTrue(toast.window === window)
        XCTAssertTrue(window.windowScene === scene)
        XCTAssertEqual(window.subviews.compactMap { $0 as? ToastView }.count, 1)
        XCTAssertEqual(toast.label.text, "전환 중 표시")
        XCTAssertFalse(toast.isHidden)
    }

    func testWindowIsAboveMainWindowAndNeverBecomesKey() throws {
        let window = try makeWindow()
        defer { window.hide() }
        let scene = try XCTUnwrap(window.windowScene)
        let main = try XCTUnwrap(scene.windows.first { $0.isKeyWindow })
        window.show(id: UUID(), message: "최상단", backgroundColor: .red)

        window.makeKey()

        XCTAssertTrue(main.windowLevel < window.windowLevel)
        XCTAssertFalse(window.canBecomeKey)
        XCTAssertFalse(window.isKeyWindow)
        XCTAssertTrue(main.isKeyWindow)
    }

    func testWindowPassesTouchesOutsideToastThrough() throws {
        let window = try makeWindow()
        defer { window.hide() }
        window.show(id: UUID(), message: "터치 전달", backgroundColor: .red)
        window.layoutIfNeeded()
        let toast = try findToast(in: window)
        let point = CGPoint(x: window.bounds.midX, y: window.bounds.maxY - 1)
        XCTAssertFalse(toast.frame.contains(point))

        XCTAssertNil(window.hitTest(point, with: nil))
    }

    func testToastUsesWindowSafeAreaAndExistingInsets() throws {
        let window = try makeWindow()
        defer { window.hide() }
        window.show(id: UUID(), message: "배치 확인", backgroundColor: .red)
        window.layoutIfNeeded()
        let toast = try findToast(in: window)

        XCTAssertEqual(toast.frame.minY, window.safeAreaInsets.top + 12, accuracy: 0.5)
        XCTAssertEqual(toast.center.x, window.bounds.midX, accuracy: 0.5)
        XCTAssertTrue(20 <= toast.frame.minX)
        XCTAssertTrue(toast.frame.maxX <= window.bounds.maxX - 20)
    }

    func testSceneDisconnectHideClearsShownState() throws {
        let window = try makeWindow()
        defer { window.hide() }
        let id = UUID()
        window.show(id: id, message: "연결 종료 전", backgroundColor: .red)

        window.hide()
        XCTAssertTrue(window.isHidden)
        window.show(id: UUID(), message: "새 표시", backgroundColor: .green)
        window.hide(id: id)

        let toast = try findToast(in: window)
        XCTAssertFalse(window.isHidden)
        XCTAssertFalse(toast.isHidden)
        XCTAssertEqual(toast.label.text, "새 표시")
    }

    private func makeWindow() throws -> ToastWindow {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        return ToastWindow(windowScene: scene)
    }

    private func findToast(in window: ToastWindow) throws -> ToastView {
        try XCTUnwrap(window.subviews.compactMap { $0 as? ToastView }.first)
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
