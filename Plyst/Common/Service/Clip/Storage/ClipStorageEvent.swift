//
//  ClipStorageEvent.swift
//  Plyst
//
//  Created by opfic on 9/28/26.
//

/// 저장이 확정된 메타데이터 변경입니다. inserted와 updated 값은 저장이 확정된 전체 스냅샷을 포함합니다.
enum ClipStorageEvent: Equatable, Sendable {
    case inserted(Clip)
    case updated(Clip)
    case deleted(Clip.ID)
}
