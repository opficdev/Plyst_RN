//
//  ClipUpdate.swift
//  Plyst
//
//  Created by opfic on 9/28/26.
//

import Foundation

enum ClipUpdate: Equatable, Sendable {

    /// 편집 가능한 상세 정보를 한 번에 교체합니다. nil은 대응하는 필드의 값을 제거하는 의미입니다.
    case details(name: String?, memo: String?, isPinned: Bool)
    /// 편집 초안을 저장할 때 최신 사용 시각을 덮어쓰지 않도록 사용 기록을 별도로 갱신합니다.
    /// matching을 전달하면 식별자와 원본, 생성 시각이 같은 클립에만 적용합니다. 상세 정보 편집은 허용합니다.
    case lastUsedAt(Date, matching: Clip? = nil)

    /// 저장소의 직렬화된 쓰기 작업 내부에서 현재 저장된 최신 클립에 적용합니다.
    func applying(to clip: Clip) -> Clip {
        switch self {
        case let .details(name, memo, isPinned):
            return Clip(
                id: clip.id,
                content: clip.content,
                name: name,
                isPinned: isPinned,
                memo: memo,
                createdAt: clip.createdAt,
                lastUsedAt: clip.lastUsedAt
            )
        case let .lastUsedAt(date, expected):
            if let expected {
                guard expected.id == clip.id,
                      expected.content == clip.content,
                      expected.createdAt == clip.createdAt else { return clip }
            }
            return Clip(
                id: clip.id,
                content: clip.content,
                name: clip.name,
                isPinned: clip.isPinned,
                memo: clip.memo,
                createdAt: clip.createdAt,
                lastUsedAt: date
            )
        }
    }
}
