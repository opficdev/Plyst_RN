//
//  TextDetailViewAction.swift
//  Plyst
//
//  Created by opfic on 10/1/26.
//

import Foundation

/// 텍스트 상세 화면의 루트 뷰가 뷰 컨트롤러로 전달하는 이벤트입니다.
enum TextDetailViewAction {
    case close
    case save
    case copy
    case delete
    case changeName(String)
    case changeMemo(String)
    case changePinned(Bool)
}
