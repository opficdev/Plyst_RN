//
//  ReuseIdentifiable.swift
//  Plyst
//
//  Created by opfic on 10/1/26.
//

import Foundation

/// 컬렉션 뷰에 등록하는 재사용 뷰의 식별자를 타입 이름으로 제공합니다.
@MainActor
protocol ReuseIdentifiable {
    static var reuseIdentifier: String { get }
}

extension ReuseIdentifiable {
    static var reuseIdentifier: String {
        String(describing: self)
    }
}
