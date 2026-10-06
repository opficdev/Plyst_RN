//
//  ClipDetailLike.swift
//  Plyst
//
//  Created by opfic on 10/3/26.
//

import UIKit

/// 클립 상세 화면의 상단 바와 카드 및 편집 요소를 요구합니다.
@MainActor
protocol ClipDetailLike: UIView {
    var closeButton: UIButton { get }
    var titleLabel: UILabel { get }
    var saveButton: UIButton { get }
    var card: UIView { get }
    var metaLabel: UILabel { get }
    var nameField: UITextField { get }
    var pinLabel: UILabel { get }
    var pinSwitch: UISwitch { get }
    var datesView: ClipDetailDatesView { get }
    var actionBar: ClipDetailActionBarView { get }
}
