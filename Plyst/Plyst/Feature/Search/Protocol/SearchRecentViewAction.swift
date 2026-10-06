//
//  SearchRecentViewAction.swift
//  Plyst
//
//  Created by opfic on 10/1/26.
//

import Foundation

/// 최근 검색어 영역이 부모 뷰로 전달하는 이벤트입니다.
enum SearchRecentViewAction {
    case select(String)
    case remove(String)
    case clear
}
