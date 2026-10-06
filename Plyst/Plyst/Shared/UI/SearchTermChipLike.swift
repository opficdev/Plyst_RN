//
//  SearchTermChipLike.swift
//  Plyst
//
//  Created by opfic on 10/3/26.
//

import UIKit

/// 최근 검색어 칩의 검색어 선택 및 삭제 버튼을 요구합니다.
@MainActor
protocol SearchTermChipLike: UIView {
    var termButton: UIButton { get }
    var removeButton: UIButton { get }
}
