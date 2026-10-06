//
//  TextDetailView.swift
//  Plyst
//
//  Created by opfic on 10/1/26.
//

import UIKit

@MainActor
final class TextDetailView: UIView, TextDetailViewLike, ClipDetailLike {
    private static let bodyAttributes: [NSAttributedString.Key: Any] = {
        let style = NSMutableParagraphStyle()
        style.minimumLineHeight = 35
        style.maximumLineHeight = 35
        return [
            .font: UIFont.systemFont(ofSize: 22, weight: .medium),
            .foregroundColor: UIColor(resource: .homePrimaryText),
            .paragraphStyle: style
        ]
    }()

    private let topBar = UIView()
    let closeButton: UIButton = DetailBarButton(style: .icon("xmark"))
    let titleLabel = UILabel()
    let saveButton: UIButton = DetailBarButton(style: .title("저장"))
    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    let card = UIView()
    let metaLabel = UILabel()
    private let textView = UITextView()
    private let fieldsStack = UIStackView()
    private let nameRow = UIStackView()
    let nameField = UITextField()
    private let pinRow = UIStackView()
    let pinLabel = UILabel()
    let pinSwitch = UISwitch()
    private let memoRow = UIStackView()
    private let memoView = UITextView()
    private let memoPlaceholder = UILabel()
    let datesView = ClipDetailDatesView()
    lazy var actionBar = ClipDetailActionBarView(
        copy: { [weak self] in self?.send(.copy) },
        delete: { [weak self] in self?.send(.delete) }
    )
    private let send: @MainActor (TextDetailViewAction) -> Void

    init(
        frame: CGRect,
        send: @escaping @MainActor (TextDetailViewAction) -> Void
    ) {
        self.send = send
        super.init(frame: frame)
        configureAppearance()
        makeHierarchy()
        makeLayout()
        bindActions()
        bindTraitChanges()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    func setContent(
        meta: String,
        text: String
    ) {
        metaLabel.text = meta
        guard textView.text != text else { return }
        textView.attributedText = NSAttributedString(string: text, attributes: Self.bodyAttributes)
    }

    func setDraft(
        name: String,
        memo: String,
        isPinned: Bool
    ) {
        // State는 입력보다 늦게 도착하므로 입력 중인 칸에 대입하면 그 사이에 입력한 글자가 사라집니다.
        if !nameField.isFirstResponder, nameField.text != name { nameField.text = name }
        if !memoView.isFirstResponder, memoView.text != memo { memoView.text = memo }
        memoPlaceholder.isHidden = !memoView.text.isEmpty
        if pinSwitch.isOn != isPinned { pinSwitch.setOn(isPinned, animated: true) }
    }

    func setDates(
        saved: String,
        lastUsed: String
    ) {
        datesView.setDates(saved: saved, lastUsed: lastUsed)
    }

    func setSaveEnabled(_ isEnabled: Bool) {
        saveButton.isEnabled = isEnabled
    }

    func setBusy(_ isBusy: Bool) {
        actionBar.setBusy(isBusy)
    }

    func focusName() {
        nameField.becomeFirstResponder()
    }

    private static func makeCaption(_ text: String) -> UILabel {
        let label = UILabel()
        label.attributedText = NSAttributedString(
            string: text,
            attributes: [
                .font: UIFont.monospacedSystemFont(ofSize: 11, weight: .semibold),
                .foregroundColor: UIColor(resource: .homeSecondaryText),
                .kern: 0.88
            ]
        )
        return label
    }

    private static func makeDivider() -> UIView {
        let divider = UIView()
        divider.backgroundColor = UIColor(resource: .homeOutline)
        divider.translatesAutoresizingMaskIntoConstraints = false
        divider.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return divider
    }

    private func configureAppearance() {
        backgroundColor = UIColor(resource: .homeCanvas)

        titleLabel.text = "텍스트"
        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        titleLabel.textColor = UIColor(resource: .homePrimaryText)

        scrollView.keyboardDismissMode = .interactive
        scrollView.alwaysBounceVertical = true
        contentStack.axis = .vertical

        card.backgroundColor = UIColor(resource: .homeCard)
        card.layer.cornerRadius = 18
        card.layer.borderWidth = 1
        metaLabel.font = .monospacedSystemFont(ofSize: 11.5, weight: .medium)
        metaLabel.textColor = UIColor(resource: .homeSecondaryText)
        textView.isEditable = false
        textView.isScrollEnabled = false
        textView.backgroundColor = .clear
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0

        fieldsStack.axis = .vertical
        for row in [nameRow, memoRow] {
            row.axis = .vertical
            row.spacing = 4
            row.isLayoutMarginsRelativeArrangement = true
            row.layoutMargins = UIEdgeInsets(
                top: 12,
                left: 4,
                bottom: 12,
                right: 4
            )
        }
        pinRow.axis = .horizontal
        pinRow.alignment = .center
        pinRow.isLayoutMarginsRelativeArrangement = true
        pinRow.layoutMargins = UIEdgeInsets(
            top: 14,
            left: 4,
            bottom: 14,
            right: 4
        )
        pinLabel.text = "고정"
        pinLabel.font = .systemFont(ofSize: 16, weight: .medium)
        pinLabel.textColor = UIColor(resource: .homePrimaryText)
        pinSwitch.onTintColor = UIColor(resource: .homeSwitchOn)

        nameField.font = .systemFont(ofSize: 17, weight: .medium)
        nameField.textColor = UIColor(resource: .homePrimaryText)
        nameField.attributedPlaceholder = NSAttributedString(
            string: "이름 없음",
            attributes: [.foregroundColor: UIColor(resource: .homePlaceholder)]
        )
        nameField.returnKeyType = .done

        memoView.font = .systemFont(ofSize: 16)
        memoView.textColor = UIColor(resource: .homePrimaryText)
        memoView.backgroundColor = .clear
        memoView.isScrollEnabled = false
        memoView.textContainerInset = .zero
        memoView.textContainer.lineFragmentPadding = 0
        memoPlaceholder.text = "이 내용을 언제 쓰는지 적어 두세요"
        memoPlaceholder.font = .systemFont(ofSize: 16)
        memoPlaceholder.textColor = UIColor(resource: .homePlaceholder)
    }

    private func makeHierarchy() {
        addSubview(scrollView)
        addSubview(actionBar)
        addSubview(topBar)

        topBar.addSubview(closeButton)
        topBar.addSubview(titleLabel)
        topBar.addSubview(saveButton)

        scrollView.addSubview(contentStack)
        card.addSubview(metaLabel)
        card.addSubview(textView)
        contentStack.addArrangedSubview(card)
        contentStack.addArrangedSubview(fieldsStack)
        contentStack.addArrangedSubview(datesView)
        contentStack.setCustomSpacing(10, after: card)
        contentStack.setCustomSpacing(18, after: fieldsStack)

        nameRow.addArrangedSubview(Self.makeCaption("이름"))
        nameRow.addArrangedSubview(nameField)
        pinRow.addArrangedSubview(pinLabel)
        pinRow.addArrangedSubview(pinSwitch)
        memoRow.addArrangedSubview(Self.makeCaption("메모"))
        memoRow.addArrangedSubview(memoView)
        memoRow.addSubview(memoPlaceholder)
        fieldsStack.addArrangedSubview(nameRow)
        fieldsStack.addArrangedSubview(Self.makeDivider())
        fieldsStack.addArrangedSubview(pinRow)
        fieldsStack.addArrangedSubview(Self.makeDivider())
        fieldsStack.addArrangedSubview(memoRow)
        fieldsStack.addArrangedSubview(Self.makeDivider())
    }

    private func makeLayout() {
        for view in [
            topBar, titleLabel, scrollView, contentStack, metaLabel, textView, memoView, memoPlaceholder
        ] {
            view.translatesAutoresizingMaskIntoConstraints = false
        }

        NSLayoutConstraint.activate([
            topBar.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 12),
            topBar.leadingAnchor.constraint(equalTo: leadingAnchor),
            topBar.trailingAnchor.constraint(equalTo: trailingAnchor),
            topBar.bottomAnchor.constraint(equalTo: closeButton.bottomAnchor, constant: 8),
            closeButton.topAnchor.constraint(equalTo: topBar.topAnchor),
            closeButton.leadingAnchor.constraint(equalTo: topBar.leadingAnchor, constant: 16),
            saveButton.centerYAnchor.constraint(equalTo: closeButton.centerYAnchor),
            saveButton.trailingAnchor.constraint(equalTo: topBar.trailingAnchor, constant: -16),
            titleLabel.centerXAnchor.constraint(equalTo: topBar.centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: closeButton.centerYAnchor),

            scrollView.topAnchor.constraint(equalTo: topBar.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: actionBar.topAnchor),
            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 8),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -28),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 16),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -16),
            contentStack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -32),

            metaLabel.topAnchor.constraint(equalTo: card.topAnchor, constant: 18),
            metaLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 20),
            metaLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -20),
            textView.topAnchor.constraint(equalTo: metaLabel.bottomAnchor, constant: 12),
            textView.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 20),
            textView.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -20),
            textView.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -22),

            memoView.heightAnchor.constraint(greaterThanOrEqualToConstant: 64),
            memoPlaceholder.topAnchor.constraint(equalTo: memoView.topAnchor),
            memoPlaceholder.leadingAnchor.constraint(equalTo: memoView.leadingAnchor),
            memoPlaceholder.trailingAnchor.constraint(lessThanOrEqualTo: memoView.trailingAnchor)
        ])
        actionBar.makeLayout(in: self)
    }

    private func bindActions() {
        closeButton.addAction(UIAction { [weak self] _ in self?.send(.close) }, for: .touchUpInside)
        saveButton.addAction(UIAction { [weak self] _ in self?.send(.save) }, for: .touchUpInside)
        nameField.addAction(
            UIAction { [weak self] _ in
                guard let self else { return }
                send(.changeName(nameField.text ?? ""))
            },
            for: .editingChanged
        )
        nameField.addAction(
            UIAction { [weak self] _ in
                guard let self else { return }
                scrollToVisible(nameRow)
            },
            for: .editingDidBegin
        )
        pinSwitch.addAction(
            UIAction { [weak self] _ in
                guard let self else { return }
                send(.changePinned(pinSwitch.isOn))
            },
            for: .valueChanged
        )
        nameField.delegate = self
        memoView.delegate = self
    }

    private func bindTraitChanges() {
        updateBorder()
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: TextDetailView, _) in
            view.updateBorder()
        }
    }

    private func updateBorder() {
        card.layer.borderColor = UIColor(resource: .homeOutline).resolvedColor(with: traitCollection).cgColor
    }

    /// 키보드에 가려지지 않도록 편집 중인 영역을 스크롤해 보이게 합니다.
    private func scrollToVisible(_ target: UIView) {
        scrollView.scrollRectToVisible(target.convert(target.bounds, to: scrollView), animated: true)
    }
}

extension TextDetailView: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }
}

extension TextDetailView: UITextViewDelegate {
    func textViewDidBeginEditing(_ textView: UITextView) {
        scrollToVisible(memoRow)
    }

    func textViewDidChange(_ textView: UITextView) {
        memoPlaceholder.isHidden = !textView.text.isEmpty
        send(.changeMemo(textView.text))
        scrollToVisible(memoRow)
    }
}
