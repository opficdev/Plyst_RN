//
//  HomeViewController.swift
//  Plyst
//
//  Created by opfic on 9/30/26.
//

import PlystBridge
import ReactBrownfield
import UIKit

/// React Native 홈을 호스팅하고 화면 이동을 연결하므로 Feature에서 PlystBridge를 직접 사용합니다.
@MainActor
final class HomeViewController: UIViewController, HomeBridgeNavigator {
    private let makeSearchViewController: @MainActor (@escaping @MainActor () -> Void) -> UIViewController
    private let makeDetailViewController: @MainActor (Clip.ID, HomeBridgeClipKind) -> UIViewController
    private let onRootViewUnavailable: @MainActor () -> Void
    private var contentView: UIView?
    private var searchViewController: UIViewController?

    init(
        makeSearchViewController: @escaping @MainActor (@escaping @MainActor () -> Void) -> UIViewController,
        makeDetailViewController: @escaping @MainActor (Clip.ID, HomeBridgeClipKind) -> UIViewController,
        onRootViewUnavailable: @escaping @MainActor () -> Void
    ) {
        self.makeSearchViewController = makeSearchViewController
        self.makeDetailViewController = makeDetailViewController
        self.onRootViewUnavailable = onRootViewUnavailable
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureAppearance()
        HomeBridge.register(self)
        HomeBridge.searchVisibilityChanged(false)
        contentView = ReactNativeBrownfield.shared.view(
            moduleName: "HomeView",
            initialProps: nil,
            launchOptions: nil
        )
        makeHierarchy()
        makeLayout()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if contentView == nil { onRootViewUnavailable() }
    }

    func openClip(
        id: Clip.ID,
        kind: HomeBridgeClipKind
    ) {
        guard presentedViewController == nil else { return }
        present(makeDetailViewController(id, kind), animated: true)
    }

    func openSearch() {
        guard searchViewController == nil else { return }
        let search = makeSearchViewController { [weak self] in self?.hideSearch() }
        embed(search)
        searchViewController = search
        HomeBridge.searchVisibilityChanged(true)
    }

    private func hideSearch() {
        guard let search = searchViewController else { return }
        removeEmbedded(search)
        searchViewController = nil
        HomeBridge.searchVisibilityChanged(false)
    }

    private func configureAppearance() {
        view.backgroundColor = UIColor(resource: .homeCanvas)
    }

    private func makeHierarchy() {
        if let contentView { view.addSubview(contentView) }
    }

    private func makeLayout() {
        guard let contentView else { return }
        contentView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            contentView.topAnchor.constraint(equalTo: view.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
}
