//
//  SearchViewAction.swift
//  Plyst
//
//  Created by opfic on 10/1/26.
//

import Foundation

/// 검색 화면의 루트 뷰가 뷰 컨트롤러로 전달하는 이벤트입니다.
enum SearchViewAction {
    case changeQuery(String)
    case submit
    case cancel
    case selectFilter(HomeFilter)
    case selectRecentTerm(String)
    case removeRecentTerm(String)
    case clearRecentTerms
}
