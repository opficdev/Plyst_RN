//
//  ToastHostWindow.swift
//  Plyst
//
//  Created by opfic on 10/8/26.
//

import OSLog
import ReactBrownfield
import UIKit

@MainActor
final class ToastHostWindow: UIWindow {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "opfic.PlystRN",
        category: String(describing: ToastHostWindow.self)
    )

    private var content: UIView?

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

    override func hitTest(
        _ point: CGPoint,
        with event: UIEvent?
    ) -> UIView? {
        nil
    }

    private func makeHierarchy() {
        let root = UIViewController()
        rootViewController = root
        guard let content = ReactNativeBrownfield.shared.view(
            moduleName: "ToastHost",
            initialProps: nil,
            launchOptions: nil
        ) else {
            Self.logger.error("ToastHost RN 뷰 생성에 실패했습니다.")
            return
        }
        self.content = content
        root.view.addSubview(content)
    }

    private func configureAppearance() {
        windowLevel = .normal + 2
        backgroundColor = .clear
        rootViewController?.view.backgroundColor = .clear
        rootViewController?.view.isOpaque = false
        content?.backgroundColor = .clear
        content?.isOpaque = false
    }

    private func makeLayout() {
        guard let content, let root = rootViewController else { return }
        content.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: root.view.topAnchor),
            content.leadingAnchor.constraint(equalTo: root.view.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: root.view.trailingAnchor),
            content.bottomAnchor.constraint(equalTo: root.view.bottomAnchor)
        ])
    }
}
