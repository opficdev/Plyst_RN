//
//  ImageDetailView.swift
//  Plyst
//
//  Created by opfic on 10/1/26.
//

import UIKit

@MainActor
final class ImageDetailView: UIView, ImageDetailViewLike, ClipDetailLike {
    private let topBar = UIView()
    let closeButton: UIButton = DetailBarButton(style: .icon("xmark"))
    let titleLabel = UILabel()
    let saveButton: UIButton = DetailBarButton(style: .title("저장"))
    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    let card = UIView()
    let metaLabel = UILabel()
    private let imageView = UIImageView()
    private let previewMessage = UILabel()
    private let failureIcon = UIImageView()
    private let photoButton = UIButton(type: .system)
    private let fieldsStack = UIStackView()
    private let nameRow = UIStackView()
    private let nameLabel = UILabel()
    let nameField = UITextField()
    private let pinRow = UIStackView()
    let pinLabel = UILabel()
    let pinSwitch = UISwitch()
    let datesView = ClipDetailDatesView()
    lazy var actionBar = ClipDetailActionBarView(
        copy: { [weak self] in self?.send(.copy) },
        delete: { [weak self] in self?.send(.delete) }
    )
    private var aspectConstraint: NSLayoutConstraint?
    private var isBusy = false
    private var isSavingToPhotos = false
    private let send: @MainActor (ImageDetailViewAction) -> Void

    init(
        frame: CGRect,
        send: @escaping @MainActor (ImageDetailViewAction) -> Void
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

    func setContent(meta: String) {
        metaLabel.text = meta
    }

    func setPreview(
        _ image: UIImage?,
        isLoading: Bool,
        didFail: Bool
    ) {
        if imageView.image !== image {
            imageView.image = image
            if let image, 0 < image.size.width {
                setAspectRatio(image.size.height / image.size.width)
            }
        }
        previewMessage.isHidden = image != nil
        failureIcon.isHidden = image != nil || !didFail
        previewMessage.text = didFail ? "이미지를 불러오지 못했습니다" : (isLoading ? "이미지를 불러오는 중입니다" : "")
    }

    func setDraft(
        name: String,
        isPinned: Bool
    ) {
        // 입력 중인 칸은 늦게 도착한 State로 덮어쓰지 않습니다.
        if !nameField.isFirstResponder, nameField.text != name { nameField.text = name }
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
        self.isBusy = isBusy
        actionBar.setBusy(isBusy)
        updatePhotoButton()
    }

    func setSavingToPhotos(_ isSaving: Bool) {
        isSavingToPhotos = isSaving
        updatePhotoButton()
    }

    private func configureAppearance() {
        backgroundColor = UIColor(resource: .homeCanvas)
        titleLabel.text = "이미지"
        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        titleLabel.textColor = UIColor(resource: .homePrimaryText)
        scrollView.keyboardDismissMode = .interactive
        scrollView.alwaysBounceVertical = true
        contentStack.axis = .vertical
        contentStack.spacing = 12
        card.backgroundColor = UIColor(resource: .homeCard)
        card.layer.cornerRadius = 22
        card.layer.borderWidth = 1
        card.clipsToBounds = true
        metaLabel.font = .monospacedSystemFont(ofSize: 12, weight: .medium)
        metaLabel.textColor = UIColor(resource: .homeSecondaryText)
        metaLabel.numberOfLines = 0
        imageView.contentMode = .scaleAspectFit
        imageView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        previewMessage.font = .systemFont(ofSize: 14)
        previewMessage.textColor = UIColor(resource: .homeSecondaryText)
        previewMessage.textAlignment = .center
        previewMessage.numberOfLines = 0
        failureIcon.image = UIImage(
            systemName: "exclamationmark.triangle",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 32, weight: .regular)
        )
        failureIcon.tintColor = UIColor(resource: .homePlaceholder)
        failureIcon.contentMode = .scaleAspectFit
        failureIcon.isHidden = true

        var photo = UIButton.Configuration.tinted()
        photo.title = "사진 앱에 저장"
        photo.image = UIImage(systemName: "square.and.arrow.down")
        photo.imagePadding = 8
        photo.baseForegroundColor = UIColor(resource: .homePrimaryText)
        photo.baseBackgroundColor = UIColor(resource: .homeCard)
        photo.contentInsets = NSDirectionalEdgeInsets(
            top: 14,
            leading: 12,
            bottom: 14,
            trailing: 12
        )
        photoButton.configuration = photo

        fieldsStack.axis = .vertical
        nameRow.axis = .vertical
        nameRow.spacing = 4
        for row in [nameRow, pinRow] {
            row.isLayoutMarginsRelativeArrangement = true
            row.layoutMargins = UIEdgeInsets(
                top: 12,
                left: 4,
                bottom: 12,
                right: 4
            )
        }
        nameLabel.text = "이름"
        nameLabel.font = .monospacedSystemFont(ofSize: 11, weight: .semibold)
        nameLabel.textColor = UIColor(resource: .homeSecondaryText)
        nameField.font = .systemFont(ofSize: 17, weight: .medium)
        nameField.textColor = UIColor(resource: .homePrimaryText)
        nameField.attributedPlaceholder = NSAttributedString(
            string: "이름 없음",
            attributes: [.foregroundColor: UIColor(resource: .homePlaceholder)]
        )
        nameField.returnKeyType = .done
        pinRow.axis = .horizontal
        pinRow.alignment = .center
        pinLabel.text = "고정"
        pinLabel.font = .systemFont(ofSize: 16, weight: .medium)
        pinLabel.textColor = UIColor(resource: .homePrimaryText)
        pinSwitch.onTintColor = UIColor(resource: .homeSwitchOn)
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
        card.addSubview(imageView)
        card.addSubview(previewMessage)
        card.addSubview(failureIcon)
        contentStack.addArrangedSubview(card)
        contentStack.addArrangedSubview(photoButton)
        contentStack.addArrangedSubview(fieldsStack)
        contentStack.addArrangedSubview(datesView)
        contentStack.setCustomSpacing(18, after: fieldsStack)
        nameRow.addArrangedSubview(nameLabel)
        nameRow.addArrangedSubview(nameField)
        pinRow.addArrangedSubview(pinLabel)
        pinRow.addArrangedSubview(pinSwitch)
        fieldsStack.addArrangedSubview(nameRow)
        fieldsStack.addArrangedSubview(Self.makeDivider())
        fieldsStack.addArrangedSubview(pinRow)
        fieldsStack.addArrangedSubview(Self.makeDivider())
    }

    private func makeLayout() {
        for view in [topBar, titleLabel, scrollView, contentStack, metaLabel, imageView, previewMessage, failureIcon] {
            view.translatesAutoresizingMaskIntoConstraints = false
        }
        // 비율보다 상한과 하한을 우선합니다. 시트가 나타나는 동안의 작은 높이에도 제약 충돌을 피합니다.
        let minimum = imageView.heightAnchor.constraint(greaterThanOrEqualToConstant: 96)
        minimum.priority = UILayoutPriority(998)
        let maximum = imageView.heightAnchor.constraint(lessThanOrEqualTo: safeAreaLayoutGuide.heightAnchor, multiplier: 0.6)
        maximum.priority = UILayoutPriority(999)
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
            metaLabel.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
            metaLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            metaLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            imageView.topAnchor.constraint(equalTo: metaLabel.bottomAnchor, constant: 12),
            imageView.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            imageView.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            imageView.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16),
            minimum,
            maximum,
            previewMessage.centerYAnchor.constraint(equalTo: imageView.centerYAnchor),
            previewMessage.leadingAnchor.constraint(equalTo: imageView.leadingAnchor),
            previewMessage.trailingAnchor.constraint(equalTo: imageView.trailingAnchor),
            failureIcon.centerXAnchor.constraint(equalTo: imageView.centerXAnchor),
            failureIcon.bottomAnchor.constraint(equalTo: previewMessage.topAnchor, constant: -6)
        ])
        setAspectRatio(0.75)
        actionBar.makeLayout(in: self)
    }

    private static func makeDivider() -> UIView {
        let divider = UIView()
        divider.backgroundColor = UIColor(resource: .homeOutline)
        divider.translatesAutoresizingMaskIntoConstraints = false
        divider.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return divider
    }

    private func setAspectRatio(_ ratio: CGFloat) {
        aspectConstraint?.isActive = false
        let constraint = imageView.heightAnchor.constraint(equalTo: imageView.widthAnchor, multiplier: ratio)
        constraint.priority = .defaultHigh
        constraint.isActive = true
        aspectConstraint = constraint
    }

    private func updatePhotoButton() {
        photoButton.isEnabled = !isBusy && !isSavingToPhotos
        photoButton.configuration?.showsActivityIndicator = isSavingToPhotos
    }

    private func bindActions() {
        closeButton.addAction(UIAction { [weak self] _ in self?.send(.close) }, for: .touchUpInside)
        saveButton.addAction(UIAction { [weak self] _ in self?.send(.save) }, for: .touchUpInside)
        photoButton.addAction(UIAction { [weak self] _ in self?.send(.saveToPhotos) }, for: .touchUpInside)
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
                scrollView.scrollRectToVisible(nameRow.convert(nameRow.bounds, to: scrollView), animated: true)
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
    }

    private func bindTraitChanges() {
        updateBorder()
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: ImageDetailView, _) in
            view.updateBorder()
        }
    }

    private func updateBorder() {
        card.layer.borderColor = UIColor(resource: .homeOutline).resolvedColor(with: traitCollection).cgColor
    }
}

extension ImageDetailView: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }
}
