//
//  HomePinnedRowView.swift
//  Plyst
//
//  Created by opfic on 9/30/26.
//

import UIKit

final class HomePinnedRowView: UICollectionReusableView, HomePinnedRowViewLike, SectionTitleLike {
    private static let titleTopInset = CGFloat(20)
    private static let rowTopInset = CGFloat(14)
    private static let bottomInset = CGFloat(16)
    private static let titleFont = UIFont.monospacedSystemFont(ofSize: 11, weight: .semibold)

    static var thumbnailDimension: CGFloat {
        HomePinnedClipView.thumbnailDimension
    }

    static var height: CGFloat {
        titleTopInset + ceil(titleFont.lineHeight) + rowTopInset + HomePinnedClipView.height + bottomInset
    }

    let title = UILabel()
    let rule = UIView()
    private let scrollView = UIScrollView()
    private let stack = UIStackView()
    private var items = [HomePinnedClipView]()
    private var clips = [Clip]()
    private var send: (@MainActor (HomePinnedRowViewAction) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureAppearance()
        makeHierarchy()
        makeLayout()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    func configure(
        clips: [Clip],
        now: Date,
        key: (Clip) -> HomeThumbnailKey?,
        thumbnail: (HomeThumbnailKey) -> HomeThumbnailPhase,
        send: @escaping @MainActor (HomePinnedRowViewAction) -> Void
    ) {
        self.send = send
        self.clips = clips
        while items.count < clips.count { items.append(makeItem()) }
        while clips.count < items.count { items.removeLast().removeFromSuperview() }

        for (index, clip) in clips.enumerated() {
            let clipKey = key(clip)
            items[index].configure(
                clip: clip,
                now: now,
                key: clipKey,
                thumbnail: clipKey.map(thumbnail) ?? .pending,
                onCopy: { [weak self] in self?.send?(.copy(clip.id)) }
            )
        }
    }

    /// 가로 스크롤 영역에 보이는 카드의 클립을 반환한다. 썸네일 요청을 화면에 보이는 카드로 한정할 때 사용한다.
    func visibleClips() -> [Clip] {
        layoutIfNeeded()
        let visible = scrollView.convert(scrollView.bounds, to: stack)
        return zip(clips, items)
            .filter { visible.intersects($0.1.frame) }
            .map(\.0)
    }

    private func makeItem() -> HomePinnedClipView {
        let item = HomePinnedClipView()
        item.translatesAutoresizingMaskIntoConstraints = false
        item.widthAnchor.constraint(equalToConstant: HomePinnedClipView.width).isActive = true
        let tap = UITapGestureRecognizer(target: self, action: #selector(didTapItem(_:)))
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(didLongPressItem(_:)))
        longPress.minimumPressDuration = 0.48
        // 길게 누르기가 인식되면 탭이 상세 화면을 함께 열지 않도록 합니다.
        tap.require(toFail: longPress)
        item.addGestureRecognizer(tap)
        item.addGestureRecognizer(longPress)
        stack.addArrangedSubview(item)
        return item
    }

    @objc private func didTapItem(_ recognizer: UITapGestureRecognizer) {
        guard let item = recognizer.view as? HomePinnedClipView,
              let index = items.firstIndex(where: { $0 === item }),
              index < clips.count else { return }
        send?(.select(clips[index]))
    }

    @objc private func didLongPressItem(_ recognizer: UILongPressGestureRecognizer) {
        guard recognizer.state == .began,
              let item = recognizer.view as? HomePinnedClipView,
              let index = items.firstIndex(where: { $0 === item }),
              index < clips.count else { return }
        send?(.showMenu(clips[index]))
    }

    private func configureAppearance() {
        title.attributedText = NSAttributedString(
            string: "고정",
            attributes: [
                .font: Self.titleFont,
                .foregroundColor: UIColor(resource: .homeSecondaryText),
                .kern: 0.88
            ]
        )
        rule.backgroundColor = UIColor(resource: .homeOutline)
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.delegate = self
        stack.axis = .horizontal
        stack.spacing = 10
    }

    private func makeHierarchy() {
        addSubview(title)
        addSubview(rule)
        addSubview(scrollView)
        scrollView.addSubview(stack)
    }

    private func makeLayout() {
        title.translatesAutoresizingMaskIntoConstraints = false
        rule.translatesAutoresizingMaskIntoConstraints = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        stack.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: topAnchor, constant: Self.titleTopInset),
            title.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            rule.centerYAnchor.constraint(equalTo: title.centerYAnchor),
            rule.leadingAnchor.constraint(equalTo: title.trailingAnchor, constant: 10),
            rule.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            rule.heightAnchor.constraint(equalToConstant: 1),
            scrollView.topAnchor.constraint(equalTo: title.bottomAnchor, constant: Self.rowTopInset),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.heightAnchor.constraint(equalToConstant: HomePinnedClipView.height),
            stack.topAnchor.constraint(equalTo: scrollView.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: -20),
            stack.heightAnchor.constraint(equalTo: scrollView.heightAnchor)
        ])
    }
}

extension HomePinnedRowView: UIScrollViewDelegate {
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        send?(.didScroll(self))
    }
}
