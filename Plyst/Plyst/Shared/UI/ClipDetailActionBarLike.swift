//
//  ClipDetailActionBarLike.swift
//  Plyst
//
//  Created by opfic on 10/3/26.
//

import UIKit

/// 클립 상세 하단 바의 구분선과 삭제 및 복사 버튼을 요구합니다.
@MainActor
protocol ClipDetailActionBarLike: UIView {
    var line: UIView { get }
    var deleteButton: UIButton { get }
    var copyButton: UIButton { get }
}
