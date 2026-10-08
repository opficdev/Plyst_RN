//
//  TextDetailViewController.swift
//  Plyst
//
//  Created by opfic on 10/8/26.
//

import PlystBridge
import ReactBrownfield
import UIKit

@MainActor
final class TextDetailViewController: UIViewController, ScreenBridgeCloser {
    private let clipID: Clip.ID
    private let topBar = UIView()
    private let closeButton = DetailBarButton(style: .icon("xmark"))
    private let titleLabel = UILabel()
    private let saveButton = DetailBarButton(style: .title("저장"))
    private var contentView: UIView?
    private var didClose = false

    init(clipID: Clip.ID) {
        self.clipID = clipID
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .pageSheet
        sheetPresentationController?.detents = [.large()]
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        ScreenBridge.register(self)
        contentView = ReactNativeBrownfield.shared.view(
            moduleName: "TextDetailView",
            initialProps: ["clipID": clipID.uuidString],
            launchOptions: nil
        )
        configureAppearance()
        makeHierarchy()
        makeLayout()
        bindActions()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if contentView == nil { close() }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.didClose else { return }
            self.dismissScreen()
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isBeingDismissed || presentingViewController == nil {
            ScreenBridge.unregister(self)
        }
    }

    func close() {
        guard !didClose, !isBeingDismissed else { return }
        didClose = true
        dismissScreen()
    }

    private func dismissScreen() {
        guard !isBeingPresented, !isBeingDismissed,
              presentingViewController != nil, viewIfLoaded?.window != nil else { return }
        dismiss(animated: true) { [weak self] in
            guard let self else { return }
            ScreenBridge.unregister(self)
        }
    }

    private func configureAppearance() {
        view.backgroundColor = UIColor(resource: .homeCanvas)
        titleLabel.text = "텍스트"
        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        titleLabel.textColor = UIColor(resource: .homePrimaryText)
        saveButton.isEnabled = false
    }

    private func makeHierarchy() {
        if let contentView { view.addSubview(contentView) }
        view.addSubview(topBar)
        topBar.addSubview(closeButton)
        topBar.addSubview(titleLabel)
        topBar.addSubview(saveButton)
    }

    private func makeLayout() {
        topBar.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            topBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            topBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            topBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            topBar.bottomAnchor.constraint(equalTo: closeButton.bottomAnchor, constant: 8),
            closeButton.topAnchor.constraint(equalTo: topBar.topAnchor),
            closeButton.leadingAnchor.constraint(equalTo: topBar.leadingAnchor, constant: 16),
            saveButton.centerYAnchor.constraint(equalTo: closeButton.centerYAnchor),
            saveButton.trailingAnchor.constraint(equalTo: topBar.trailingAnchor, constant: -16),
            titleLabel.centerXAnchor.constraint(equalTo: topBar.centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: closeButton.centerYAnchor)
        ])
        guard let contentView else { return }
        contentView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            contentView.topAnchor.constraint(equalTo: topBar.bottomAnchor),
            contentView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func bindActions() {
        closeButton.addAction(UIAction { [weak self] _ in self?.close() }, for: .touchUpInside)
    }
}
