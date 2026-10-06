//
//  ToastLike.swift
//  Plyst
//
//  Created by opfic on 10/3/26.
//

import UIKit

/// 토스트 메시지를 표시하는 레이블을 요구합니다.
@MainActor
protocol ToastLike: UIView {
    var label: UILabel { get }
}
