//
//  ClipTaskCancellation.swift
//  Plyst
//
//  Created by opfic on 11/7/26.
//

import PlystCore

/// 실행 중인 Task의 취소 상태를 코어 판정 지점에 전달
final class ClipTaskCancellation: ClipCancellationSource {
    func isCancelled() -> Bool { Task.isCancelled }
}
