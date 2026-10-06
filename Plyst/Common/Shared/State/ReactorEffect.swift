//
//  ReactorEffect.swift
//  Plyst
//
//  Created by opfic on 9/28/26.
//

import RxSwift

enum ReactorEffect {

    /// Capture the service, not the Reactor, so releasing the Reactor can cancel the request.
    static func task<Element: Sendable>(
        _ operation: @escaping @Sendable () async throws -> Element
    ) -> Observable<Element> {
        Single<Element>.create(work: operation)
            .asObservable()
            .catch { error in
                if error is CancellationError {
                    return .empty()
                }
                return .error(error)
            }
    }

    /// Calls the stream factory for each subscription. The service owns its producer's termination handler.
    static func stream<Sequence: AsyncSequence & Sendable>(
        _ make: @escaping @Sendable () -> Sequence
    ) -> Observable<Sequence.Element> where Sequence.Element: Sendable {
        .deferred { make().asObservable() }
    }

    /// Owns a producer Task and cancels it when the stream terminates or its Rx subscription is disposed.
    static func stream<Element: Sendable>(
        bufferingPolicy: AsyncThrowingStream<Element, Error>.Continuation.BufferingPolicy = .unbounded,
        produce: @escaping @Sendable (AsyncThrowingStream<Element, Error>.Continuation) async throws -> Void
    ) -> Observable<Element> {
        stream {
            AsyncThrowingStream(Element.self, bufferingPolicy: bufferingPolicy) { continuation in
                // Producers run independently of UI isolation and only send Sendable values.
                let task = Task.detached {
                    do {
                        try Task.checkCancellation()
                        try await produce(continuation)
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
                continuation.onTermination = { _ in task.cancel() }
            }
        }
    }
}
