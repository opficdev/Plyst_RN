//
//  SectionTitleLike.swift
//  Plyst
//
//  Created by opfic on 10/3/26.
//

import UIKit

/// 섹션 제목과 구분선을 요구합니다.
@MainActor
protocol SectionTitleLike: UIView {
    var title: UILabel { get }
    var rule: UIView { get }
}
