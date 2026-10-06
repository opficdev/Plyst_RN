//
//  HomePinnedRowViewAction.swift
//  Plyst
//
//  Created by opfic on 10/1/26.
//

import Foundation

/// 고정 행이 뷰 컨트롤러로 전달하는 이벤트입니다.
enum HomePinnedRowViewAction {
    case didScroll(any HomePinnedRowViewLike)
    case select(Clip)
    case showMenu(Clip)
    case copy(Clip.ID)
}
