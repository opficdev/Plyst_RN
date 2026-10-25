//
//  ClipUpdate.swift
//  Plyst
//
//  Created by opfic on 9/28/26.
//

import Foundation

enum ClipUpdate: Equatable, Sendable {
    /// 편집 가능한 상세 정보를 한 번에 교체함
    /// nil은 대응하는 필드의 값을 제거하는 의미
    /// 새로 고정하면 요청 시각을 기록함
    /// 이미 고정되어 있으면 기존 고정 시각을 유지하고 해제하면 제거함
    case details(name: String?, memo: String?, isPinned: Bool, requestedAt: Date)
    /// 편집 초안을 저장할 때 최신 사용 시각을 덮어쓰지 않도록 사용 기록을 별도로 갱신함
    /// matching을 전달하면 식별자와 원본, 생성 시각이 같은 클립에만 적용함
    /// 상세 정보 편집은 허용함
    case lastUsedAt(Date, matching: Clip? = nil)

    /// 저장소의 직렬화된 쓰기 작업 내부에서 현재 저장된 최신 클립에 적용함
    func applying(to clip: Clip) -> Clip {
        switch self {
        case let .details(name, memo, isPinned, requestedAt):
            return Clip(
                id: clip.id,
                content: clip.content,
                name: name,
                pinnedAt: isPinned ? (clip.pinnedAt ?? requestedAt) : nil,
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
                pinnedAt: clip.pinnedAt,
                memo: clip.memo,
                createdAt: clip.createdAt,
                lastUsedAt: date
            )
        }
    }
}
