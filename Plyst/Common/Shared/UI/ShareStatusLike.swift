//
//  ShareStatusLike.swift
//  Plyst
//
//  Created by opfic on 10/3/26.
//

import UIKit

/// 공유 상태 표시와 재시도 및 취소 버튼을 요구합니다.
@MainActor
protocol ShareStatusLike: UIView {
    var checkmarkView: UIImageView { get }
    var indicator: UIActivityIndicatorView { get }
    var titleLabel: UILabel { get }
    var retryButton: UIButton { get }
    var cancelButton: UIButton { get }
}
