//
//  HomeViewAction.swift
//  Plyst
//
//  Created by opfic on 10/1/26.
//

import Foundation

/// 기록 화면의 루트 뷰가 뷰 컨트롤러로 전달하는 이벤트입니다.
enum HomeViewAction {
    case save
    case search
    case selectFilter(HomeFilter)
    case showMenu(IndexPath)
}
