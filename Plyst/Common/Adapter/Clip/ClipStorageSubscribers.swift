//
//  ClipStorageSubscribers.swift
//  Plyst
//
//  Created by opfic on 11/6/26.
//

import Foundation
import os
import PlystCore

/// 코어의 변경 알림을 구독자에게 전달
/// 코어가 이 객체를 강한 참조로 보관하므로 어댑터를 참조하지 않음
/// 연결 잠금을 쥔 채 호출되므로 코어를 호출하거나 대기하지 않음
final class ClipStorageSubscribers: ClipChangeListener {
    private let continuations = OSAllocatedUnfairLock(initialState: [UUID: AsyncStream<ClipStorageEvent>.Continuation]())

    deinit {
        continuations.withLock { $0.values.forEach { $0.finish() } }
    }

    func changed(change: ClipChangeValue) {
        guard let event = ClipStorageEvent(coreValue: change) else { return }
        continuations.withLock { $0.values.forEach { $0.yield(event) } }
    }

    func subscribe() -> AsyncStream<ClipStorageEvent> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<ClipStorageEvent>.makeStream(bufferingPolicy: .unbounded)
        continuations.withLock { $0[id] = continuation }
        continuation.onTermination = { [weak self] _ in
            self?.continuations.withLock { $0[id] = nil }
        }
        return stream
    }
}

private extension ClipStorageEvent {
    /// 코어가 검사한 식별자라 변환은 실패하지 않음
    init?(coreValue value: ClipChangeValue) {
        switch value {
        case .inserted(let clip):
            guard let clip = Clip(coreValue: clip) else { return nil }
            self = .inserted(clip)
        case .updated(let clip):
            guard let clip = Clip(coreValue: clip) else { return nil }
            self = .updated(clip)
        case .deleted(let id):
            guard let id = UUID(uuidString: id) else { return nil }
            self = .deleted(id)
        }
    }
}
