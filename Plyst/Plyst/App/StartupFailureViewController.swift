//
//  StartupFailureViewController.swift
//  Plyst
//
//  Created by opfic on 9/30/26.
//

import UIKit

@MainActor
final class StartupFailureViewController: UIViewController {
    private let onRetry: @MainActor () -> Void

    init(onRetry: @escaping @MainActor () -> Void) {
        self.onRetry = onRetry
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(resource: .homeCanvas)

        let title = UILabel()
        title.text = "기록을 열지 못했습니다"
        title.font = .systemFont(ofSize: 21, weight: .bold)
        title.textColor = UIColor(resource: .homePrimaryText)
        title.textAlignment = .center

        let button = UIButton(type: .system)
        button.setTitle("다시 시도", for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        button.addAction(UIAction { [weak self] _ in
            self?.onRetry()
        }, for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [title, button])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 20
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 32),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -32)
        ])
    }
}
