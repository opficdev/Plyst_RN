//
//  HomeEmptyStateLike.swift
//  Plyst
//
//  Created by opfic on 10/3/26.
//

import UIKit

/// 빈 목록의 제목과 설명을 요구합니다.
@MainActor
protocol HomeEmptyStateLike: UIStackView {
    var emptyTitle: UILabel { get }
    var emptyBody: UILabel { get }
}
