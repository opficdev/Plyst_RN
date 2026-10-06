//
//  Clip.swift
//  Plyst
//
//  Created by opfic on 9/28/26.
//

import Foundation

/// 저장된 클립의 불변 스냅샷입니다. 추가 이후 콘텐츠와 생성 시각은 변경되지 않습니다.
struct Clip: Equatable, Identifiable, Sendable {

    let id: UUID
    let content: ClipContent
    let name: String?
    let isPinned: Bool
    let memo: String?
    let createdAt: Date
    /// 클립을 다시 복사하는 작업이 성공하기 전까지는 nil입니다.
    let lastUsedAt: Date?

    init(
        id: UUID = UUID(),
        content: ClipContent,
        name: String? = nil,
        isPinned: Bool = false,
        memo: String? = nil,
        createdAt: Date = Date(),
        lastUsedAt: Date? = nil
    ) {
        self.id = id
        self.content = content
        self.name = name
        self.isPinned = isPinned
        self.memo = memo
        self.createdAt = createdAt
        self.lastUsedAt = lastUsedAt
    }
}
