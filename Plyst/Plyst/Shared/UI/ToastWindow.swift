//
//  ToastWindow.swift
//  Plyst
//
//  Created by opfic on 10/4/26.
//

import UIKit

/// 같은 Scene의 화면과 모달 위에 토스트를 표시합니다. 터치는 아래 창으로 전달합니다.
@MainActor
final class ToastWindow: UIWindow {
    private let toast = ToastView(textColor: UIColor(resource: .homeBottomText))
    private var presentedID: UUID?

    override var canBecomeKey: Bool { false }

    override init(windowScene: UIWindowScene) {
        super.init(windowScene: windowScene)
        makeHierarchy()
        configureAppearance()
        makeLayout()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    func show(
        id: UUID,
        message: String,
        backgroundColor: UIColor
    ) {
        presentedID = id
        isHidden = false
        toast.show(message: message, backgroundColor: backgroundColor)
    }

    /// 이전 토스트의 타이머나 화면 상태가 새 토스트를 숨기지 않도록 식별자를 확인합니다.
    func hide(id: UUID) {
        guard presentedID == id else { return }
        presentedID = nil
        toast.hide()
    }

    /// Scene 연결이 끊어지면 표시 상태를 비우고 창을 숨깁니다.
    func hide() {
        presentedID = nil
        toast.hide()
        isHidden = true
    }

    override func hitTest(
        _ point: CGPoint,
        with event: UIEvent?
    ) -> UIView? {
        guard let view = super.hitTest(point, with: event),
              view === toast || view.isDescendant(of: toast) else { return nil }
        return view
    }

    private func makeHierarchy() {
        rootViewController = UIViewController()
        addSubview(toast)
    }

    private func configureAppearance() {
        backgroundColor = .clear
        rootViewController?.view.backgroundColor = .clear
        windowLevel = .normal + 1
    }

    private func makeLayout() {
        toast.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            toast.centerXAnchor.constraint(equalTo: centerXAnchor),
            toast.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 12),
            toast.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 20),
            toast.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -20)
        ])
    }
}
