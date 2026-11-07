//
//  Clip.swift
//  Plyst
//
//  Created by opfic on 9/28/26.
//

import Foundation
import PlystCore

/// 저장된 클립의 불변 스냅샷
/// 추가 이후 콘텐츠와 생성 시각은 변경되지 않음
struct Clip: Equatable, Identifiable, Sendable {
    let id: UUID
    let content: ClipContent
    let name: String?
    let pinnedAt: Date?
    let memo: String?
    let createdAt: Date
    /// 클립을 다시 복사하는 작업이 성공하기 전까지는 nil
    let lastUsedAt: Date?

    init(
        id: UUID = UUID(),
        content: ClipContent,
        name: String? = nil,
        pinnedAt: Date? = nil,
        memo: String? = nil,
        createdAt: Date = Date(),
        lastUsedAt: Date? = nil
    ) {
        self.id = id
        self.content = content
        self.name = name
        self.pinnedAt = pinnedAt
        self.memo = memo
        self.createdAt = createdAt
        self.lastUsedAt = lastUsedAt
    }

    /// 식별자가 UUID 형식이 아니면 nil
    init?(coreValue value: ClipValue) {
        guard let id = UUID(uuidString: value.id), let content = ClipContent(coreValue: value.content) else { return nil }
        self.init(
            id: id,
            content: content,
            name: value.name,
            pinnedAt: value.pinnedAt.map(Date.init(timeIntervalSinceReferenceDate:)),
            memo: value.memo,
            createdAt: Date(timeIntervalSinceReferenceDate: value.createdAt),
            lastUsedAt: value.lastUsedAt.map(Date.init(timeIntervalSinceReferenceDate:))
        )
    }

    var coreValue: ClipValue {
        ClipValue(
            id: id.uuidString,
            content: content.coreValue,
            name: name,
            pinnedAt: pinnedAt?.timeIntervalSinceReferenceDate,
            memo: memo,
            createdAt: createdAt.timeIntervalSinceReferenceDate,
            lastUsedAt: lastUsedAt?.timeIntervalSinceReferenceDate
        )
    }
}
