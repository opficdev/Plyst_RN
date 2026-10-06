//
//  ActionSheetLike.swift
//  Plyst
//
//  Created by opfic on 10/3/26.
//

import UIKit

/// 액션 시트의 배경과 카드 및 제목과 메시지 요소를 요구합니다.
@MainActor
protocol ActionSheetLike: UIView {
    var scrimView: UIView { get }
    var cardView: UIView { get }
    var titleLabel: UILabel { get }
    var messageLabel: UILabel { get }
}
