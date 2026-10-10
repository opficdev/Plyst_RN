//
//  HomeFilter.swift
//  Plyst
//
//  Created by opfic on 9/30/26.
//

import Foundation

enum HomeFilter: CaseIterable, Equatable, Sendable {
    case all
    case text
    case image
    case pinned

    var title: String {
        switch self {
        case .all: "전체"
        case .text: "텍스트"
        case .image: "이미지"
        case .pinned: "고정"
        }
    }

    func includes(_ clip: Clip) -> Bool {
        switch self {
        case .all:
            true
        case .text:
            if case .text = clip.content { true } else { false }
        case .image:
            if case .image = clip.content { true } else { false }
        case .pinned:
            clip.isPinned
        }
    }
}
