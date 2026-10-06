//
//  HomeViewController+QuickAction.swift
//  Plyst
//
//  Created by opfic on 10/1/26.
//

import ReactorKit
import RxSwift
import UIKit

extension HomeViewController {
    /// 이미 상세 화면이 떠 있으면 다시 열지 않습니다.
    func showDetail(for clip: Clip) {
        guard presentedViewController == nil else { return }
        present(makeDetailViewController(clip), animated: true)
    }

    /// 길게 누른 시점의 클립으로 작업 메뉴를 표시합니다. 메뉴가 modal로 떠 있는 동안에는 아래 카드의 선택과 길게 누르기가 전달되지 않습니다.
    /// 취소와 배경 탭은 Action을 보내지 않으므로 데이터가 바뀌지 않습니다.
    func showMenu(for clip: Clip) {
        guard presentedViewController == nil else { return }
        let menu = ActionSheetViewController(
            title: Self.menuTitle(for: clip),
            message: Self.menuSummary(for: clip),
            items: [
                ActionSheetItem(
                    title: clip.isPinned ? "고정 해제" : "고정",
                    role: .default,
                    handler: { [weak self] in self?.reactor.action.onNext(.setPinned(clip.id, !clip.isPinned)) }
                ),
                ActionSheetItem(
                    title: "삭제",
                    role: .destructive,
                    handler: { [weak self] in self?.confirmDelete(clip) }
                ),
                ActionSheetItem(title: "취소", role: .cancel)
            ]
        )
        present(menu, animated: true)
    }

    private static func menuTitle(for clip: Clip) -> String {
        switch clip.content {
        case .text: "텍스트"
        case .image: "이미지"
        }
    }

    /// 이름이 있으면 이름을 표시하고 없으면 텍스트는 본문 앞부분을 이미지는 안내 문구를 표시합니다.
    private static func menuSummary(for clip: Clip) -> String {
        if let name = clip.name { return name }
        switch clip.content {
        case .text(let text): return String(text.prefix(60))
        case .image: return "이름 없는 이미지"
        }
    }

    private func confirmDelete(_ clip: Clip) {
        let alert = ActionSheetViewController(
            title: "이 \(Self.menuTitle(for: clip))를 삭제할까요?",
            message: "삭제하면 되돌릴 수 없습니다.",
            items: [
                ActionSheetItem(
                    title: "삭제",
                    role: .destructive,
                    handler: { [weak self] in self?.reactor.action.onNext(.delete(clip.id)) }
                ),
                ActionSheetItem(title: "취소", role: .cancel)
            ]
        )
        present(alert, animated: true)
    }
}
