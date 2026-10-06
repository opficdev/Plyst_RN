//
//  ShareStatusView.swift
//  ShareExtension
//
//  Created by opfic on 10/1/26.
//

import UIKit

@MainActor
final class ShareStatusView: UIView, ShareStatusLike {
    private let stack = UIStackView()
    let checkmarkView = UIImageView()
    let indicator = UIActivityIndicatorView(style: .medium)
    let titleLabel = UILabel()
    let retryButton = UIButton(type: .system)
    let cancelButton = UIButton(type: .system)
    private let send: @MainActor (ShareStatusViewAction) -> Void

    init(
        frame: CGRect,
        send: @escaping @MainActor (ShareStatusViewAction) -> Void
    ) {
        self.send = send
        super.init(frame: frame)
        configureAppearance()
        makeHierarchy()
        makeLayout()
        bindActions()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    func setStatus(_ status: ShareStatus) {
        switch status {
        case .saving:
            checkmarkView.isHidden = true
            indicator.startAnimating()
            titleLabel.text = "저장 중"
            retryButton.isHidden = true
            cancelButton.isHidden = false
            cancelButton.setTitle("취소", for: .normal)
        case .completed:
            checkmarkView.isHidden = false
            indicator.stopAnimating()
            titleLabel.text = "저장했습니다"
            retryButton.isHidden = true
            cancelButton.isHidden = true
        case .failed:
            checkmarkView.isHidden = true
            indicator.stopAnimating()
            titleLabel.text = "저장하지 못했습니다"
            retryButton.isHidden = false
            cancelButton.isHidden = false
            cancelButton.setTitle("닫기", for: .normal)
        }
    }

    private func makeHierarchy() {
        stack.addArrangedSubview(checkmarkView)
        stack.addArrangedSubview(indicator)
        stack.addArrangedSubview(titleLabel)
        stack.addArrangedSubview(retryButton)
        stack.addArrangedSubview(cancelButton)
        addSubview(stack)
    }

    private func configureAppearance() {
        backgroundColor = .systemBackground
        checkmarkView.image = UIImage(systemName: "checkmark.circle.fill")
        checkmarkView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 44)
        checkmarkView.tintColor = .systemGreen
        checkmarkView.isHidden = true
        titleLabel.font = .systemFont(ofSize: 21, weight: .bold)
        titleLabel.textColor = .label
        titleLabel.textAlignment = .center
        retryButton.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        retryButton.setTitle("다시 시도", for: .normal)
        retryButton.isHidden = true
        cancelButton.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 20
    }

    private func makeLayout() {
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: safeAreaLayoutGuide.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: safeAreaLayoutGuide.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: safeAreaLayoutGuide.leadingAnchor, constant: 32),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: safeAreaLayoutGuide.trailingAnchor, constant: -32)
        ])
    }

    private func bindActions() {
        retryButton.addAction(UIAction { [weak self] _ in
            self?.send(.retry)
        }, for: .touchUpInside)
        cancelButton.addAction(UIAction { [weak self] _ in
            self?.send(.cancel)
        }, for: .touchUpInside)
    }
}
