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

    var emptyTitle: String {
        switch self {
        case .all: "아직 저장된 내용이 없습니다"
        case .text: "저장된 텍스트가 없습니다"
        case .image: "저장된 이미지가 없습니다"
        case .pinned: "고정한 항목이 없습니다"
        }
    }

    var emptyMessage: String {
        switch self {
        case .all: "텍스트나 이미지를 복사한 뒤 현재 클립보드 저장을 눌러보세요"
        case .text: "텍스트를 복사한 뒤 현재 클립보드 저장을 눌러보세요"
        case .image: "이미지를 복사한 뒤 현재 클립보드 저장을 눌러보세요"
        case .pinned: "항목을 길게 눌러 고정할 수 있어요"
        }
    }
}
