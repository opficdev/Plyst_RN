//
//  ClipboardSaveResult.swift
//  Plyst
//
//  Created by opfic on 9/29/26.
//

import Foundation

enum ClipboardSaveResult: Equatable, Sendable {
    case saved(Clip)
    /// 이미지 원본과 클립 기록은 저장됐지만 pending 표시 파일을 제거하지 못했음
    /// recoverPendingCleanup()을 호출해야 정리를 다시 시도
    case savedWithPendingCleanup(Clip, fileID: UUID)
    case empty
    case unsupported
    case accessFailed
    case invalidImage
}
