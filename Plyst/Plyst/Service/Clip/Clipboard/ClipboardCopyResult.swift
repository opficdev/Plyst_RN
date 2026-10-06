//
//  ClipboardCopyResult.swift
//  Plyst
//
//  Created by opfic on 9/29/26.
//

import Foundation

enum ClipboardUsageUpdateFailure: Equatable, Sendable {
    case cancelled
    case storage(ClipStorageError)
    /// 같은 식별자가 다른 원본 또는 생성 시각의 클립으로 교체되어 사용 기록을 적용하지 않았습니다.
    case replaced
    /// 저장 서비스의 계약에 포함되지 않은 오류입니다. 원본 오류 내용은 노출하지 않습니다.
    case unknown
}

enum ClipboardCopyResult: Equatable, Sendable {
    /// 클립보드 쓰기를 확인했고 사용 시각의 저장도 확정했습니다.
    case copied(Clip)
    case writeNotObserved(Clip.ID)
    /// 쓰기는 확인했지만 사용 시각을 저장하지 못했습니다. 자동으로 다시 복사하거나 되돌리지 않습니다.
    case copiedWithoutLastUsedAt(clip: Clip, copiedAt: Date, failure: ClipboardUsageUpdateFailure)
}
