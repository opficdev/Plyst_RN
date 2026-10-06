//
//  ClipDetailActionBarView.swift
//  Plyst
//
//  Created by opfic on 10/1/26.
//

import UIKit

/// 화면 하단에 고정되는 삭제와 다시 복사 버튼 바입니다.
/// 하단 가장자리는 키보드가 올라오면 키보드 위로 따라 올라갑니다.
final class ClipDetailActionBarView: UIView, ClipDetailActionBarLike {
    let line = UIView()
    private let stack = UIStackView()
    let deleteButton = UIButton(type: .system)
    let copyButton = UIButton(type: .system)
    private let copy: @MainActor () -> Void
    private let delete: @MainActor () -> Void

    init(
        copy: @escaping @MainActor () -> Void,
        delete: @escaping @MainActor () -> Void
    ) {
        self.copy = copy
        self.delete = delete
        super.init(frame: .zero)
        configureAppearance()
        makeHierarchy()
        bindActions()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    func setBusy(_ isBusy: Bool) {
        deleteButton.isEnabled = !isBusy
        copyButton.isEnabled = !isBusy
        stack.alpha = isBusy ? 0.55 : 1
    }

    /// 부모의 레이아웃 가이드에 맞춰 제약을 만듭니다. 부모 계층에 추가한 뒤 호출해야 합니다.
    func makeLayout(
        in parent: UIView
    ) {
        translatesAutoresizingMaskIntoConstraints = false
        line.translatesAutoresizingMaskIntoConstraints = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        // 시트가 화면 아래에서 올라오는 동안에는 키보드 가이드가 뷰 위쪽에 있어 필수 제약으로 두면 충돌합니다.
        // 우선순위를 낮추고 키보드가 없을 때의 위치를 그보다 낮은 우선순위로 함께 둡니다.
        let keyboard = stack.bottomAnchor.constraint(equalTo: parent.keyboardLayoutGuide.topAnchor, constant: -12)
        keyboard.priority = UILayoutPriority(999)
        let resting = stack.bottomAnchor.constraint(equalTo: parent.safeAreaLayoutGuide.bottomAnchor, constant: -12)
        resting.priority = UILayoutPriority(998)
        NSLayoutConstraint.activate([
            keyboard,
            resting,
            leadingAnchor.constraint(equalTo: parent.leadingAnchor),
            trailingAnchor.constraint(equalTo: parent.trailingAnchor),
            bottomAnchor.constraint(equalTo: parent.bottomAnchor),
            topAnchor.constraint(equalTo: stack.topAnchor, constant: -12),
            line.topAnchor.constraint(equalTo: topAnchor),
            line.leadingAnchor.constraint(equalTo: leadingAnchor),
            line.trailingAnchor.constraint(equalTo: trailingAnchor),
            line.heightAnchor.constraint(equalToConstant: 1),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            deleteButton.widthAnchor.constraint(equalToConstant: 84),
            deleteButton.heightAnchor.constraint(equalToConstant: 54),
            copyButton.heightAnchor.constraint(equalToConstant: 54)
        ])
    }

    private func configureAppearance() {
        backgroundColor = UIColor(resource: .homeCanvas)
        line.backgroundColor = UIColor(resource: .homeOutline)
        stack.axis = .horizontal
        stack.spacing = 10

        var delete = UIButton.Configuration.plain()
        var deleteTitle = AttributedString("삭제")
        deleteTitle.font = .systemFont(ofSize: 16, weight: .semibold)
        delete.attributedTitle = deleteTitle
        delete.baseForegroundColor = UIColor(resource: .homeFeedbackFailure)
        delete.background.backgroundColor = UIColor(resource: .homeCard)
        delete.background.strokeColor = UIColor(resource: .homeOutline)
        delete.background.strokeWidth = 1
        delete.background.cornerRadius = 16
        delete.cornerStyle = .fixed
        deleteButton.configuration = delete

        var copy = UIButton.Configuration.plain()
        var copyTitle = AttributedString("다시 복사")
        copyTitle.font = .systemFont(ofSize: 17, weight: .semibold)
        copy.attributedTitle = copyTitle
        copy.image = UIImage(
            systemName: "doc.on.doc",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
        )
        copy.imagePadding = 8
        copy.baseForegroundColor = UIColor(resource: .homeBottomText)
        copy.background.backgroundColor = UIColor(resource: .homeBottomBar)
        copy.background.cornerRadius = 16
        copy.cornerStyle = .fixed
        copyButton.configuration = copy
    }

    private func makeHierarchy() {
        addSubview(line)
        addSubview(stack)
        stack.addArrangedSubview(deleteButton)
        stack.addArrangedSubview(copyButton)
    }

    private func bindActions() {
        deleteButton.addAction(UIAction { [weak self] _ in self?.delete() }, for: .touchUpInside)
        copyButton.addAction(UIAction { [weak self] _ in self?.copy() }, for: .touchUpInside)
    }
}
