//
//  ToastView.swift
//  Plyst
//
//  Created by opfic on 9/30/26.
//

import UIKit

/// 상단에서 내려오며 나타나고 올라가며 사라지는 메시지 토스트입니다. 표시 시간과 색상 선택은 호출부가 결정합니다.
@MainActor
final class ToastView: UIView, ToastLike {
    let label = UILabel()
    private var isVisible = false
    private var animationID = UUID()

    init(textColor: UIColor) {
        super.init(frame: .zero)
        label.textColor = textColor
        configureAppearance()
        makeHierarchy()
        makeLayout()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    func show(
        message: String,
        backgroundColor: UIColor
    ) {
        animationID = UUID()
        isVisible = true
        label.text = message
        self.backgroundColor = backgroundColor
        superview?.layoutIfNeeded()

        layer.removeAllAnimations()
        UIView.performWithoutAnimation {
            transform = hiddenTransform()
            alpha = 0
            isHidden = false
        }

        UIView.animate(
            withDuration: 0.25,
            delay: 0,
            options: [.allowUserInteraction, .curveEaseOut],
            animations: { [weak self] in
                self?.transform = .identity
                self?.alpha = 1
            }
        )
    }

    func hide() {
        guard isVisible else { return }
        isVisible = false
        let id = UUID()
        animationID = id
        superview?.layoutIfNeeded()
        let transform = hiddenTransform()

        UIView.animate(
            withDuration: 0.2,
            delay: 0,
            options: [.beginFromCurrentState, .allowUserInteraction, .curveEaseIn],
            animations: { [weak self] in
                self?.transform = transform
                self?.alpha = 0
            },
            completion: { [weak self] _ in
                guard let self,
                      animationID == id,
                      !isVisible else { return }
                isHidden = true
                self.transform = .identity
                alpha = 1
            }
        )
    }

    private func hiddenTransform() -> CGAffineTransform {
        CGAffineTransform(
            translationX: 0,
            y: -16
        )
    }

    private func configureAppearance() {
        layer.cornerRadius = 12
        isHidden = true
        isUserInteractionEnabled = false
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.textAlignment = .center
        label.numberOfLines = 0
    }

    private func makeHierarchy() {
        addSubview(label)
    }

    private func makeLayout() {
        label.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: topAnchor, constant: 11),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -11),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14)
        ])
    }
}
