//
//  EdgeFadeView.swift
//  Plyst
//
//  Created by opfic on 10/1/26.
//

import UIKit

/// 화면 가장자리에서 배경색으로 서서히 이어지는 그라데이션 뷰입니다.
/// 스크롤 영역 위에 덮어 스크롤하는 내용이 가장자리에서 자연스럽게 사라지게 합니다.
/// 터치는 아래 뷰로 전달됩니다.
final class EdgeFadeView: UIView {
    enum Edge {
        case top
        case bottom
    }

    override static var layerClass: AnyClass {
        CAGradientLayer.self
    }

    private let edge: Edge
    private let color: UIColor

    init(
        edge: Edge,
        color: UIColor
    ) {
        self.edge = edge
        self.color = color
        super.init(frame: .zero)
        configureAppearance()
        bindTraitChanges()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    private func configureAppearance() {
        isUserInteractionEnabled = false
        guard let gradient = layer as? CAGradientLayer else { preconditionFailure("layerClass registration mismatch") }
        gradient.startPoint = CGPoint(x: 0.5, y: 0)
        gradient.endPoint = CGPoint(x: 0.5, y: 1)
        // 가장자리 쪽은 불투명으로 유지하고 안쪽으로 갈수록 투명해집니다.
        switch edge {
        case .top: gradient.locations = [0, 0.65, 1]
        case .bottom: gradient.locations = [0, 0.35, 1]
        }
        updateColors()
    }

    private func bindTraitChanges() {
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: EdgeFadeView, _) in
            view.updateColors()
        }
    }

    private func updateColors() {
        guard let gradient = layer as? CAGradientLayer else { return }
        let opaque = color.resolvedColor(with: traitCollection)
        // 투명 구간도 같은 색의 알파 0 값을 써서 보간 중에 검은색이 섞이지 않게 합니다.
        let clear = opaque.withAlphaComponent(0)
        switch edge {
        case .top: gradient.colors = [opaque.cgColor, opaque.cgColor, clear.cgColor]
        case .bottom: gradient.colors = [clear.cgColor, opaque.cgColor, opaque.cgColor]
        }
    }
}
