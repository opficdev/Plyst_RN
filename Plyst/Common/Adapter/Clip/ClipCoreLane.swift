//
//  ClipCoreLane.swift
//  Plyst
//
//  Created by opfic on 11/7/26.
//

import Foundation

/// 코어 호출을 전용 직렬 큐에서 실행하는 줄
/// 코어 잠금 대기가 협력 스레드를 막지 않게 함
actor ClipCoreLane {
    private let queue: DispatchSerialQueue

    nonisolated var unownedExecutor: UnownedSerialExecutor { queue.asUnownedSerialExecutor() }

    init(label: String) {
        queue = DispatchSerialQueue(label: label)
    }

    func run<Value: Sendable>(_ operation: @Sendable () throws -> Value) throws -> Value {
        try operation()
    }
}
