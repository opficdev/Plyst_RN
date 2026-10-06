//
//  HomePinnedClipView.swift
//  Plyst
//
//  Created by opfic on 9/30/26.
//

import UIKit

final class HomePinnedClipView: UIView, ClipCardLike {
    static let width = CGFloat(252)
    static let height = CGFloat(76)
    static let thumbnailDimension = CGFloat(56)

    private static let nameFont = UIFont.systemFont(ofSize: 13, weight: .semibold)
    private static let metadataFont = UIFont.monospacedSystemFont(ofSize: 9.5, weight: .medium)

    let card = UIView()
    private let visualBox = UIView()
    private let thumbnailView = UIImageView()
    private let failureIcon = HomeCardFormat.makeFailureIcon(pointSize: 22)
    private let quote = UILabel()
    private let linkIcon = UIImageView()
    let name = UILabel()
    let metadata = UILabel()
    private lazy var textStack = UIStackView(arrangedSubviews: [name, metadata])
    let copyButton: UIButton = HomeCopyButton()
    private var onCopy: (() -> Void)?

    private(set) var representedKey: HomeThumbnailKey?

    override init(frame: CGRect) {
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

    override func didMoveToWindow() {
        super.didMoveToWindow()
        updateBorder()
    }

    func configure(
        clip: Clip,
        now: Date,
        key: HomeThumbnailKey?,
        thumbnail: HomeThumbnailPhase,
        onCopy: @escaping () -> Void
    ) {
        self.onCopy = onCopy
        switch clip.content {
        case .text(let text):
            representedKey = nil
            let isWebLink = clip.content.isWebLink
            quote.isHidden = isWebLink
            linkIcon.isHidden = !isWebLink
            thumbnailView.isHidden = true
            failureIcon.isHidden = true
            name.text = clip.name ?? text
            metadata.text = "텍스트 · \(HomeCardFormat.time(for: clip.createdAt, now: now))"

        case .image:
            representedKey = key
            quote.isHidden = true
            linkIcon.isHidden = true
            thumbnailView.isHidden = false
            thumbnailView.image = thumbnail.image
            failureIcon.isHidden = !thumbnail.isFailed
            name.text = clip.name ?? "이름 없는 이미지"
            metadata.text = "이미지 · \(HomeCardFormat.time(for: clip.createdAt, now: now))"
        }
    }

    private func configureAppearance() {
        card.backgroundColor = UIColor(resource: .homeCard)
        card.layer.masksToBounds = true
        card.layer.cornerRadius = 16
        card.layer.borderWidth = 1

        visualBox.backgroundColor = UIColor(resource: .homeImageBackground)
        visualBox.layer.masksToBounds = true
        visualBox.layer.cornerRadius = 10

        thumbnailView.contentMode = .scaleAspectFit

        quote.text = "“"
        quote.font = UIFont(name: "Georgia-Bold", size: 20) ?? .systemFont(ofSize: 20, weight: .bold)
        quote.textColor = UIColor(resource: .homeMarkBackground)
        quote.textAlignment = .center

        linkIcon.image = HomeCardFormat.linkIcon(pointSize: 24)
        linkIcon.tintColor = UIColor(resource: .homeMarkBackground)
        linkIcon.contentMode = .scaleAspectFit
        linkIcon.isHidden = true

        name.font = Self.nameFont
        name.textColor = UIColor(resource: .homePrimaryText)
        name.lineBreakMode = .byTruncatingTail
        name.numberOfLines = 1

        metadata.font = Self.metadataFont
        metadata.textColor = UIColor(resource: .homeSecondaryText)
        metadata.lineBreakMode = .byTruncatingTail
        metadata.numberOfLines = 1

        textStack.axis = .vertical
        textStack.spacing = 4
    }

    private func makeHierarchy() {
        addSubview(card)
        card.addSubview(visualBox)
        visualBox.addSubview(thumbnailView)
        visualBox.addSubview(quote)
        visualBox.addSubview(linkIcon)
        visualBox.addSubview(failureIcon)
        card.addSubview(textStack)
        card.addSubview(copyButton)
    }

    private func makeLayout() {
        card.translatesAutoresizingMaskIntoConstraints = false
        visualBox.translatesAutoresizingMaskIntoConstraints = false
        thumbnailView.translatesAutoresizingMaskIntoConstraints = false
        quote.translatesAutoresizingMaskIntoConstraints = false
        linkIcon.translatesAutoresizingMaskIntoConstraints = false
        failureIcon.translatesAutoresizingMaskIntoConstraints = false
        textStack.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            card.topAnchor.constraint(equalTo: topAnchor),
            card.leadingAnchor.constraint(equalTo: leadingAnchor),
            card.trailingAnchor.constraint(equalTo: trailingAnchor),
            card.bottomAnchor.constraint(equalTo: bottomAnchor),
            visualBox.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 10),
            visualBox.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            visualBox.widthAnchor.constraint(equalToConstant: Self.thumbnailDimension),
            visualBox.heightAnchor.constraint(equalToConstant: Self.thumbnailDimension),
            thumbnailView.topAnchor.constraint(equalTo: visualBox.topAnchor),
            thumbnailView.leadingAnchor.constraint(equalTo: visualBox.leadingAnchor),
            thumbnailView.trailingAnchor.constraint(equalTo: visualBox.trailingAnchor),
            thumbnailView.bottomAnchor.constraint(equalTo: visualBox.bottomAnchor),
            quote.centerXAnchor.constraint(equalTo: visualBox.centerXAnchor),
            quote.centerYAnchor.constraint(equalTo: visualBox.centerYAnchor),
            linkIcon.centerXAnchor.constraint(equalTo: visualBox.centerXAnchor),
            linkIcon.centerYAnchor.constraint(equalTo: visualBox.centerYAnchor),
            linkIcon.widthAnchor.constraint(equalToConstant: 28),
            linkIcon.heightAnchor.constraint(equalToConstant: 28),
            failureIcon.centerXAnchor.constraint(equalTo: visualBox.centerXAnchor),
            failureIcon.centerYAnchor.constraint(equalTo: visualBox.centerYAnchor),
            textStack.leadingAnchor.constraint(equalTo: visualBox.trailingAnchor, constant: 10),
            textStack.trailingAnchor.constraint(equalTo: copyButton.leadingAnchor, constant: -8),
            textStack.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            copyButton.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -10),
            copyButton.centerYAnchor.constraint(equalTo: card.centerYAnchor)
        ])
    }

    private func bindActions() {
        copyButton.addAction(UIAction { [weak self] _ in
            self?.onCopy?()
        }, for: .touchUpInside)
    }

    private func bindTraitChanges() {
        updateBorder()
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: HomePinnedClipView, _) in
            view.updateBorder()
        }
    }

    private func updateBorder() {
        card.layer.borderColor = UIColor(resource: .homeOutline).resolvedColor(with: traitCollection).cgColor
    }
}
