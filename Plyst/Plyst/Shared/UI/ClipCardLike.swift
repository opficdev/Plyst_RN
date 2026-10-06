//
//  ClipCardLike.swift
//  Plyst
//
//  Created by opfic on 10/3/26.
//

import UIKit

/// 클립 카드의 표면과 이름 및 메타데이터와 복사 버튼을 요구합니다.
@MainActor
protocol ClipCardLike: UIView {
    var card: UIView { get }
    var name: UILabel { get }
    var metadata: UILabel { get }
    var copyButton: UIButton { get }
}
