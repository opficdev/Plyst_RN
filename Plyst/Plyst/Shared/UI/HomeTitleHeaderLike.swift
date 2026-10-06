//
//  HomeTitleHeaderLike.swift
//  Plyst
//
//  Created by opfic on 10/3/26.
//

import UIKit

/// 홈 제목 헤더의 표시와 제목 및 검색 버튼을 요구합니다.
@MainActor
protocol HomeTitleHeaderLike: UIView {
    var mark: UIImageView { get }
    var title: UILabel { get }
    var searchButton: UIButton { get }
}
