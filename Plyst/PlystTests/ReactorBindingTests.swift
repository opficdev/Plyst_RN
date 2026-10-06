//
//  ReactorBindingTests.swift
//  PlystTests
//
//  Created by opfic on 9/28/26.
//

import ReactorKit
import RxSwift
import UIKit
import XCTest
@testable import Plyst

@MainActor
final class ReactorBindingTests: XCTestCase {

    func testStateIsRenderedAndObservationIsCancelledWhenControllerIsReleased() async {
        let rendered = expectation(description: "Updated state is rendered")
        let disposed = expectation(description: "State observation is disposed")
        let spy = StateSubscriptionReactorSpy(onDispose: { disposed.fulfill() })
        var controller: StateSubscriptionTestViewController? = StateSubscriptionTestViewController(reactor: spy) { state in
            if state.isReady {
                rendered.fulfill()
            }
        }
        weak let weakController = controller

        controller?.loadViewIfNeeded()
        spy.states.onNext(.init(isReady: true))
        await fulfillment(of: [rendered], timeout: 2)
        XCTAssertEqual(controller?.states, [.init(), .init(isReady: true)])

        controller = nil
        XCTAssertNil(weakController)
        await fulfillment(of: [disposed], timeout: 2)
    }

    func testAsyncResultIsReducedOnMainThread() async {
        let reduced = expectation(description: "Async result is reduced on the main thread")
        let service = AsyncServiceTestDriver(load: {
            await Task.detached { true }.value
        })
        let reactor = AsyncServiceTestReactor(service: service) {
            XCTAssertTrue(Thread.isMainThread)
            reduced.fulfill()
        }

        reactor.action.onNext(.load)
        await fulfillment(of: [reduced], timeout: 2)
        XCTAssertTrue(reactor.currentState.isReady)
    }

    func testAsyncRequestIsCancelledWhenReactorIsReleased() async {
        let started = expectation(description: "Async request has started")
        let cancelled = expectation(description: "Async request is cancelled")
        let service = AsyncServiceTestDriver(load: {
            started.fulfill()
            do {
                try await Task.sleep(for: .seconds(60))
                return true
            } catch {
                if Task.isCancelled {
                    cancelled.fulfill()
                }
                throw error
            }
        })
        var reactor: AsyncServiceTestReactor? = AsyncServiceTestReactor(service: service)
        weak let weakReactor = reactor

        reactor?.action.onNext(.load)
        await fulfillment(of: [started], timeout: 2)
        reactor = nil

        XCTAssertNil(weakReactor)
        await fulfillment(of: [cancelled], timeout: 2)
    }

    func testEffectProducerIsCancelledWhenSubscriptionIsDisposed() async {
        let started = expectation(description: "Effect producer has started")
        let cancelled = expectation(description: "Effect producer is cancelled")
        let effect: Observable<Bool> = ReactorEffect.stream { _ in
            started.fulfill()
            do {
                try await Task.sleep(for: .seconds(60))
            } catch {
                if Task.isCancelled {
                    cancelled.fulfill()
                }
                throw error
            }
        }

        let subscription = effect.subscribe()
        await fulfillment(of: [started], timeout: 2)
        subscription.dispose()
        await fulfillment(of: [cancelled], timeout: 2)
    }

    func testServiceFailureBecomesMutationAndSubsequentValuesAreReduced() async {
        let failed = expectation(description: "Service failure is reduced")
        let reduced = expectation(description: "Both failure and subsequent value are reduced")
        reduced.expectedFulfillmentCount = 2
        let service = AsyncServiceTestDriver(
            load: { throw AsyncServiceTestError.failed },
            values: {
                AsyncStream { continuation in
                    continuation.yield(true)
                    continuation.finish()
                }
            }
        )
        let reactor = AsyncServiceTestReactor(service: service) { reduced.fulfill() }
        let subscription = reactor.state
            .filter { $0.hasFailed }
            .take(1)
            .subscribe(onNext: { _ in failed.fulfill() })
        defer { subscription.dispose() }

        reactor.action.onNext(.load)
        await fulfillment(of: [failed], timeout: 2)
        reactor.action.onNext(.observe)
        await fulfillment(of: [reduced], timeout: 2)
        XCTAssertTrue(reactor.currentState.hasFailed)
        XCTAssertTrue(reactor.currentState.isReady)
    }

    func testStreamProducerIsCancelledWhenReactorIsReleased() async {
        let started = expectation(description: "Stream producer has started")
        let cancelled = expectation(description: "Stream producer is cancelled")
        let service = AsyncServiceTestDriver(values: {
            AsyncStream { continuation in
                let task = Task {
                    started.fulfill()
                    do {
                        try await Task.sleep(for: .seconds(60))
                        continuation.finish()
                    } catch {
                        if Task.isCancelled {
                            cancelled.fulfill()
                        }
                        continuation.finish()
                    }
                }
                continuation.onTermination = { _ in task.cancel() }
            }
        })
        var reactor: AsyncServiceTestReactor? = AsyncServiceTestReactor(service: service)
        weak let weakReactor = reactor

        reactor?.action.onNext(.observe)
        await fulfillment(of: [started], timeout: 2)
        reactor = nil

        XCTAssertNil(weakReactor)
        await fulfillment(of: [cancelled], timeout: 2)
    }
}

private final class StateSubscriptionReactorSpy: Reactorable {

    typealias Action = Never

    struct State: Equatable, Sendable {
        var isReady = false
    }

    let initialState = State()
    let states = BehaviorSubject(value: State())
    private let onDispose: () -> Void

    var state: Observable<State> {
        states.do(onDispose: onDispose)
    }

    init(onDispose: @escaping () -> Void) {
        self.onDispose = onDispose
    }
}

@MainActor
private final class StateSubscriptionTestViewController: ReactorViewController<StateSubscriptionReactorSpy> {

    private(set) var states = [StateSubscriptionReactorSpy.State]()
    private let onRender: (StateSubscriptionReactorSpy.State) -> Void

    init(reactor: StateSubscriptionReactorSpy, onRender: @escaping (StateSubscriptionReactorSpy.State) -> Void) {
        self.onRender = onRender
        super.init(reactor: reactor)
    }

    override func render(state: StateSubscriptionReactorSpy.State) {
        states.append(state)
        onRender(state)
    }
}

private struct AsyncServiceTestDriver: Sendable {

    let load: @Sendable () async throws -> Bool
    let values: @Sendable () -> AsyncStream<Bool>

    init(
        load: @escaping @Sendable () async throws -> Bool = { true },
        values: @escaping @Sendable () -> AsyncStream<Bool> = { AsyncStream { $0.finish() } }
    ) {
        self.load = load
        self.values = values
    }
}

private enum AsyncServiceTestError: Error {
    case failed
}

private final class AsyncServiceTestReactor: Reactorable {

    enum Action: Sendable {
        case load
        case observe
    }

    enum Mutation: Sendable {
        case setReady(Bool)
        case setFailed
    }

    struct State: Sendable {
        var isReady = false
        var hasFailed = false
    }

    let initialState = State()
    private let service: AsyncServiceTestDriver
    private let onReduce: @Sendable () -> Void

    init(service: AsyncServiceTestDriver, onReduce: @escaping @Sendable () -> Void = {}) {
        self.service = service
        self.onReduce = onReduce
    }

    func mutate(action: Action) -> Observable<Mutation> {
        // Retaining the service is safe. Retaining the Reactor here prevents cancellation on release.
        let service = service
        let values: Observable<Bool>
        switch action {
        case .load:
            values = ReactorEffect.task(service.load)
        case .observe:
            values = ReactorEffect.stream(service.values)
        }
        return values
            .map(Mutation.setReady)
            .catch { _ in .just(.setFailed) }
    }

    func reduce(state: State, mutation: Mutation) -> State {
        var state = state
        switch mutation {
        case .setReady(let isReady):
            state.isReady = isReady
        case .setFailed:
            state.hasFailed = true
        }
        onReduce()
        return state
    }
}
