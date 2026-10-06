//
//  ActionSheetItem.swift
//  Plyst
//
//  Created by opfic on 10/2/26.
//

import Foundation

/// 공용 액션 시트에 표시할 항목입니다. 문구와 역할과 선택 시 동작을 호출부가 전달합니다.
struct ActionSheetItem {
    enum Role {
        case `default`
        case destructive
        case cancel
    }

    let title: String
    let role: Role
    /// 시트가 닫힌 뒤에 실행됩니다. 이 안에서 다른 시트나 화면을 표시해도 됩니다.
    var handler: @MainActor () -> Void = {}
}
