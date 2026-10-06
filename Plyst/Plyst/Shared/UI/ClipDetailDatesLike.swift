//
//  ClipDetailDatesLike.swift
//  Plyst
//
//  Created by opfic on 10/3/26.
//

import UIKit

/// 클립의 저장 날짜와 마지막 사용 날짜를 표시하는 레이블을 요구합니다.
@MainActor
protocol ClipDetailDatesLike: UIView {
    var savedValue: UILabel { get }
    var lastUsedValue: UILabel { get }
}
