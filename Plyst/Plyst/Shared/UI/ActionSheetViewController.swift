//
//  ActionSheetViewController.swift
//  Plyst
//
//  Created by opfic on 10/2/26.
//

import UIKit

/// 앱 디자인에 맞춘 공용 액션 시트를 전체 화면 위에 표시합니다.
/// 전체 화면을 덮으므로 시트가 열려 있는 동안 아래 화면의 선택과 길게 누르기는 전달되지 않습니다.
/// 항목 선택과 취소는 시트가 닫힌 뒤에 호출부 핸들러로 전달됩니다.
@MainActor
final class ActionSheetViewController: UIViewController {
    private let sheetTitle: String
    private let sheetMessage: String
    private let items: [ActionSheetItem]
    private lazy var sheetView = ActionSheetView(
        title: sheetTitle,
        message: sheetMessage,
        items: items,
        select: { [weak self] in self?.finish(with: $0) },
        cancel: { [weak self] in self?.finish(with: self?.items.last { $0.role == .cancel }) }
    )
    private var didFinish = false

    /// 취소 항목은 전달 순서와 관계없이 마지막에 표시합니다.
    init(
        title: String,
        message: String,
        items: [ActionSheetItem]
    ) {
        sheetTitle = title
        sheetMessage = message
        self.items = items.filter { $0.role != .cancel } + items.filter { $0.role == .cancel }
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
        modalTransitionStyle = .crossDissolve
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    override func loadView() {
        view = sheetView
    }

    /// 아래 화면의 텍스트 입력이 초점을 유지해 시트 위에서도 입력을 받는 일을 막습니다.
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        presentingViewController?.view.endEditing(true)
    }

    /// 처음 한 번의 선택만 받아 빠른 연속 탭이 같은 Action을 두 번 보내지 않게 합니다.
    private func finish(with item: ActionSheetItem?) {
        guard !didFinish else { return }
        didFinish = true
        dismiss(animated: true) { item?.handler() }
    }
}
