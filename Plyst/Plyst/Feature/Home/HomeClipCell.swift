//
//  HomeClipCell.swift
//  Plyst
//
//  Created by opfic on 9/30/26.
//

import UIKit

final class HomeTextCell: UICollectionViewCell, HomeTextCellLike, ClipCardLike {
    static let nameFont = UIFont.systemFont(ofSize: 14.5, weight: .semibold)
    static let bodyFont = UIFont.systemFont(ofSize: 14.5)
    private static let metadataFont = UIFont.monospacedSystemFont(ofSize: 10.5, weight: .medium)

    let card = UIView()
    private let quote = UILabel()
    private let linkIcon = UIImageView()
    let name = UILabel()
    private let body = UILabel()
    let metadata = UILabel()
    let copyButton: UIButton = HomeCopyButton()
    private lazy var metadataRow = UIStackView(arrangedSubviews: [metadata, copyButton])
    private lazy var stack = UIStackView(arrangedSubviews: [name, body, metadataRow])
    private var onCopy: (() -> Void)?

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

    override func prepareForReuse() {
        super.prepareForReuse()
        onCopy = nil
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        updateBorder()
    }

    /// name과 body는 검색 결과처럼 강조 서식이 필요할 때만 전달합니다. 전달하지 않으면 clip의 원문을 그대로 표시합니다.
    /// onCopy를 전달하면 메타데이터 행 오른쪽에 복사 버튼을 표시합니다.
    func configure(
        with clip: Clip,
        now: Date,
        name attributedName: NSAttributedString? = nil,
        body attributedBody: NSAttributedString? = nil,
        onCopy: (() -> Void)? = nil
    ) {
        guard case .text(let text) = clip.content else { return }
        let isWebLink = clip.content.isWebLink
        quote.isHidden = isWebLink
        linkIcon.isHidden = !isWebLink
        if let attributedName {
            name.attributedText = attributedName
        } else {
            // attributedText를 설정하면 레이블의 글꼴이 강조 글꼴로 바뀌므로, 재사용된 셀에서 기본 글꼴을 다시 지정합니다.
            name.font = Self.nameFont
            name.text = clip.name
        }
        name.isHidden = clip.name == nil
        body.textColor = clip.name == nil
            ? UIColor(resource: .homePrimaryText)
            : UIColor(resource: .homeNamedBodyText)
        if let attributedBody {
            body.attributedText = attributedBody
        } else {
            body.font = Self.bodyFont
            body.text = text
        }
        body.numberOfLines = clip.name == nil ? 3 : 2
        metadata.text = "텍스트 · \(HomeCardFormat.time(for: clip.createdAt, now: now))"
        self.onCopy = onCopy
        copyButton.isHidden = onCopy == nil
        // 복사 버튼이 자리를 차지하므로 메타데이터를 2줄까지 허용합니다. 2줄 높이가 버튼 높이 안에 들어가므로 카드 높이는 그대로입니다.
        // 좁은 화면에서 시각이 긴 항목은 2줄로도 다 들어가지 않아 끝이 말줄임될 수 있습니다.
        metadata.numberOfLines = onCopy == nil ? 1 : 2
    }

    static func height(
        for clip: Clip,
        width: CGFloat,
        name attributedName: NSAttributedString? = nil,
        body attributedBody: NSAttributedString? = nil,
        showsCopy: Bool = false
    ) -> CGFloat {
        guard case .text(let text) = clip.content else { return 0 }
        let available = width - 26
        let lines = clip.name == nil ? 3 : 2
        let bodyHeight = attributedBody.map {
            HomeCardFormat.height(for: $0, font: bodyFont, width: available, lines: lines)
        } ?? HomeCardFormat.height(for: text, font: bodyFont, width: available, lines: lines)
        let nameHeight = clip.name.map { plain in
            let height = attributedName.map {
                HomeCardFormat.height(for: $0, font: nameFont, width: available, lines: 2)
            } ?? HomeCardFormat.height(for: plain, font: nameFont, width: available, lines: 2)
            return height + 6
        } ?? 0
        let metadataHeight = max(ceil(metadataFont.lineHeight), showsCopy ? HomeCopyButton.side : 0)
        return 26 + 10 + nameHeight + bodyHeight + 10 + metadataHeight + 12
    }

    private func configureAppearance() {
        card.backgroundColor = UIColor(resource: .homeCard)
        card.layer.masksToBounds = true
        card.layer.cornerRadius = 18
        card.layer.borderWidth = 1

        quote.text = "“"
        quote.font = UIFont(name: "Georgia-Bold", size: 26) ?? .systemFont(ofSize: 26, weight: .bold)
        quote.textColor = UIColor(resource: .homeMarkBackground)

        linkIcon.image = HomeCardFormat.linkIcon(pointSize: 20)
        linkIcon.tintColor = UIColor(resource: .homeMarkBackground)
        linkIcon.contentMode = .scaleAspectFit
        linkIcon.isHidden = true

        name.font = Self.nameFont
        name.textColor = UIColor(resource: .homePrimaryText)
        name.lineBreakMode = .byTruncatingTail
        name.numberOfLines = 2

        body.font = Self.bodyFont
        body.lineBreakMode = .byTruncatingTail
        body.numberOfLines = 3

        metadata.font = Self.metadataFont
        metadata.textColor = UIColor(resource: .homeSecondaryText)
        metadata.lineBreakMode = .byTruncatingTail
        metadata.numberOfLines = 1

        metadataRow.axis = .horizontal
        metadataRow.alignment = .center
        metadataRow.spacing = 8
        copyButton.isHidden = true

        stack.axis = .vertical
        stack.spacing = 6
        stack.setCustomSpacing(10, after: body)
    }

    private func makeHierarchy() {
        contentView.addSubview(card)
        card.addSubview(quote)
        card.addSubview(linkIcon)
        card.addSubview(stack)
    }

    private func makeLayout() {
        card.translatesAutoresizingMaskIntoConstraints = false
        quote.translatesAutoresizingMaskIntoConstraints = false
        linkIcon.translatesAutoresizingMaskIntoConstraints = false
        stack.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            card.topAnchor.constraint(equalTo: contentView.topAnchor),
            card.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            card.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            card.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            // 26pt 따옴표 영역(상단 14pt 포함, 줄 높이 0.6배)에 맞춰 기준선을 둔다.
            quote.firstBaselineAnchor.constraint(equalTo: card.topAnchor, constant: 31),
            quote.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            linkIcon.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            linkIcon.topAnchor.constraint(equalTo: card.topAnchor, constant: 12),
            linkIcon.widthAnchor.constraint(equalToConstant: 22),
            linkIcon.heightAnchor.constraint(equalToConstant: 22),
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 36),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -12)
        ])
    }

    private func bindActions() {
        copyButton.addAction(UIAction { [weak self] _ in
            self?.onCopy?()
        }, for: .touchUpInside)
    }

    private func bindTraitChanges() {
        updateBorder()
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (cell: HomeTextCell, _) in
            cell.updateBorder()
        }
    }

    private func updateBorder() {
        card.layer.borderColor = UIColor(resource: .homeOutline).resolvedColor(with: traitCollection).cgColor
    }
}

final class HomeImageCell: UICollectionViewCell, HomeImageCellLike, ClipCardLike {
    private static let nameFont = UIFont.systemFont(ofSize: 14.5, weight: .semibold)
    private static let metadataFont = UIFont.monospacedSystemFont(ofSize: 10.5, weight: .medium)

    let card = UIView()
    private let imageBox = UIView()
    private let imageView = UIImageView()
    private let placeholder = UIView()
    private let placeholderDot = UIView()
    private let failureIcon = HomeCardFormat.makeFailureIcon(pointSize: 28)
    let name = UILabel()
    let metadata = UILabel()
    let copyButton: UIButton = HomeCopyButton()
    private lazy var metadataRow = UIStackView(arrangedSubviews: [metadata, copyButton])
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

    override func prepareForReuse() {
        super.prepareForReuse()
        representedKey = nil
        onCopy = nil
        setThumbnail(.pending)
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        updateBorder()
    }

    /// name은 검색 결과처럼 강조 서식이 필요할 때만 전달합니다. 전달하지 않으면 clip의 이름을 그대로 표시합니다.
    /// onCopy를 전달하면 메타데이터 행 오른쪽에 복사 버튼을 표시합니다.
    func configure(
        with clip: Clip,
        now: Date,
        key: HomeThumbnailKey,
        thumbnail: HomeThumbnailPhase,
        name attributedName: NSAttributedString? = nil,
        onCopy: (() -> Void)? = nil
    ) {
        guard case .image(let image) = clip.content else { return }
        representedKey = key
        name.textColor = clip.name == nil
            ? UIColor(resource: .homeUnnamedText)
            : UIColor(resource: .homePrimaryText)
        if let attributedName {
            name.attributedText = attributedName
        } else {
            name.font = Self.nameFont
            name.text = clip.name ?? "이름 없는 이미지"
        }
        metadata.text = "이미지 · \(image.pixelWidth)×\(image.pixelHeight) · \(HomeCardFormat.time(for: clip.createdAt, now: now))"
        self.onCopy = onCopy
        copyButton.isHidden = onCopy == nil
        metadata.numberOfLines = onCopy == nil ? 1 : 2
        setThumbnail(thumbnail)
    }

    func setThumbnail(_ thumbnail: HomeThumbnailPhase) {
        imageView.image = thumbnail.image
        placeholder.isHidden = !thumbnail.isPending
        failureIcon.isHidden = !thumbnail.isFailed
    }

    static func height(
        for clip: Clip,
        width: CGFloat,
        name attributedName: NSAttributedString? = nil,
        showsCopy: Bool = false
    ) -> CGFloat {
        let text = clip.name ?? "이름 없는 이미지"
        let nameHeight = attributedName.map {
            HomeCardFormat.height(for: $0, font: nameFont, width: width - 26, lines: 2)
        } ?? HomeCardFormat.height(for: text, font: nameFont, width: width - 26, lines: 2)
        let metadataHeight = max(ceil(metadataFont.lineHeight), showsCopy ? HomeCopyButton.side : 0)
        return 6 + (width - 12) + 10 + nameHeight + 10 + metadataHeight + 12
    }

    private func configureAppearance() {
        card.backgroundColor = UIColor(resource: .homeCard)
        card.layer.masksToBounds = true
        card.layer.cornerRadius = 18
        card.layer.borderWidth = 1

        imageBox.backgroundColor = UIColor(resource: .homeImageBackground)
        imageBox.layer.masksToBounds = true
        imageBox.layer.cornerRadius = 13

        imageView.contentMode = .scaleAspectFit

        placeholder.layer.cornerRadius = 3
        placeholder.layer.borderWidth = 1.5
        placeholderDot.backgroundColor = UIColor(resource: .homePlaceholder)
        placeholderDot.layer.cornerRadius = 2.5

        name.font = Self.nameFont
        name.lineBreakMode = .byTruncatingTail
        name.numberOfLines = 2

        metadata.font = Self.metadataFont
        metadata.textColor = UIColor(resource: .homeSecondaryText)
        metadata.lineBreakMode = .byTruncatingTail
        metadata.numberOfLines = 1

        metadataRow.axis = .horizontal
        metadataRow.alignment = .center
        metadataRow.spacing = 8
        copyButton.isHidden = true
    }

    private func makeHierarchy() {
        contentView.addSubview(card)
        card.addSubview(imageBox)
        imageBox.addSubview(placeholder)
        placeholder.addSubview(placeholderDot)
        imageBox.addSubview(imageView)
        imageBox.addSubview(failureIcon)
        card.addSubview(name)
        card.addSubview(metadataRow)
    }

    private func makeLayout() {
        card.translatesAutoresizingMaskIntoConstraints = false
        imageBox.translatesAutoresizingMaskIntoConstraints = false
        imageView.translatesAutoresizingMaskIntoConstraints = false
        placeholder.translatesAutoresizingMaskIntoConstraints = false
        placeholderDot.translatesAutoresizingMaskIntoConstraints = false
        failureIcon.translatesAutoresizingMaskIntoConstraints = false
        name.translatesAutoresizingMaskIntoConstraints = false
        metadataRow.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            card.topAnchor.constraint(equalTo: contentView.topAnchor),
            card.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            card.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            card.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            imageBox.topAnchor.constraint(equalTo: card.topAnchor, constant: 6),
            imageBox.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 6),
            imageBox.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -6),
            imageBox.heightAnchor.constraint(equalTo: imageBox.widthAnchor),
            imageView.topAnchor.constraint(equalTo: imageBox.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: imageBox.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: imageBox.trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: imageBox.bottomAnchor),
            placeholder.centerXAnchor.constraint(equalTo: imageBox.centerXAnchor),
            placeholder.centerYAnchor.constraint(equalTo: imageBox.centerYAnchor),
            placeholder.widthAnchor.constraint(equalToConstant: 24),
            placeholder.heightAnchor.constraint(equalToConstant: 18),
            placeholderDot.topAnchor.constraint(equalTo: placeholder.topAnchor, constant: 4),
            placeholderDot.leadingAnchor.constraint(equalTo: placeholder.leadingAnchor, constant: 5),
            placeholderDot.widthAnchor.constraint(equalToConstant: 5),
            placeholderDot.heightAnchor.constraint(equalToConstant: 5),
            failureIcon.centerXAnchor.constraint(equalTo: imageBox.centerXAnchor),
            failureIcon.centerYAnchor.constraint(equalTo: imageBox.centerYAnchor),
            name.topAnchor.constraint(equalTo: imageBox.bottomAnchor, constant: 10),
            name.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            name.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12),
            metadataRow.topAnchor.constraint(equalTo: name.bottomAnchor, constant: 10),
            metadataRow.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            metadataRow.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12),
            metadataRow.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -12)
        ])
    }

    private func bindActions() {
        copyButton.addAction(UIAction { [weak self] _ in
            self?.onCopy?()
        }, for: .touchUpInside)
    }

    private func bindTraitChanges() {
        updateBorder()
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (cell: HomeImageCell, _) in
            cell.updateBorder()
        }
    }

    private func updateBorder() {
        card.layer.borderColor = UIColor(resource: .homeOutline).resolvedColor(with: traitCollection).cgColor
        placeholder.layer.borderColor = UIColor(resource: .homePlaceholder).resolvedColor(with: traitCollection).cgColor
    }
}
