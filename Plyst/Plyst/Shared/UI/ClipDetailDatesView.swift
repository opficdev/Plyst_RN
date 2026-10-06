//
//  ClipDetailDatesView.swift
//  Plyst
//
//  Created by opfic on 10/1/26.
//

import UIKit

/// 저장한 날짜와 마지막 사용 시각을 두 칸으로 나란히 표시합니다.
final class ClipDetailDatesView: UIView, ClipDetailDatesLike {
    private let stack = UIStackView()
    let savedValue = UILabel()
    let lastUsedValue = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureAppearance()
        makeHierarchy()
        makeLayout()
        bindTraitChanges()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    func setDates(
        saved: String,
        lastUsed: String
    ) {
        savedValue.text = saved
        lastUsedValue.text = lastUsed
    }

    private static func makeCell(
        caption: String,
        value: UILabel
    ) -> UIView {
        let cell = UIView()
        cell.backgroundColor = UIColor(resource: .homeCard)
        let label = UILabel()
        label.text = caption
        label.font = .systemFont(ofSize: 12)
        label.textColor = UIColor(resource: .homeSecondaryText)
        let stack = UIStackView(arrangedSubviews: [label, value])
        stack.axis = .vertical
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: cell.topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: cell.bottomAnchor, constant: -12),
            stack.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -14)
        ])
        return cell
    }

    private func configureAppearance() {
        // 칸 사이의 1pt 간격으로 구분선을 표현합니다.
        backgroundColor = UIColor(resource: .homeOutline)
        layer.cornerRadius = 14
        layer.borderWidth = 1
        clipsToBounds = true
        stack.axis = .horizontal
        stack.distribution = .fillEqually
        stack.spacing = 1
        for value in [savedValue, lastUsedValue] {
            value.font = .monospacedSystemFont(ofSize: 14, weight: .medium)
            value.textColor = UIColor(resource: .homePrimaryText)
            value.numberOfLines = 0
        }
    }

    private func makeHierarchy() {
        addSubview(stack)
        stack.addArrangedSubview(Self.makeCell(caption: "저장한 날짜", value: savedValue))
        stack.addArrangedSubview(Self.makeCell(caption: "마지막 사용", value: lastUsedValue))
    }

    private func makeLayout() {
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])
    }

    private func bindTraitChanges() {
        updateBorder()
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: ClipDetailDatesView, _) in
            view.updateBorder()
        }
    }

    private func updateBorder() {
        layer.borderColor = UIColor(resource: .homeOutline).resolvedColor(with: traitCollection).cgColor
    }
}
