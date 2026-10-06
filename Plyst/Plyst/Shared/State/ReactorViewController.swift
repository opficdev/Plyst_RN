//
//  ReactorViewController.swift
//  Plyst
//
//  Created by opfic on 9/28/26.
//

import ReactorKit
import RxSwift
import UIKit

@MainActor
class ReactorViewController<R: Reactor>: UIViewController where R.State: Sendable {

    let reactor: R
    private var task: Task<Void, Never>?

    init(reactor: R) {
        self.reactor = reactor
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    deinit {
        task?.cancel()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        subscribe()
    }

    func render(state: R.State) {}

    func handleStateSubscriptionError(_ error: any Error) {
        assertionFailure("State subscription failed: \(error)")
    }

    private func subscribe() {
        guard task == nil else { return }

        // Capture the stream, not the Reactor or ViewController, while awaiting values.
        let values = reactor.state.values
        task = Task { [weak self] in
            do {
                for try await state in values {
                    guard !Task.isCancelled else { return }
                    self?.render(state: state)
                }
            } catch is CancellationError {
                // Cancelling observation is a normal part of the view lifecycle.
            } catch {
                guard !Task.isCancelled else { return }
                self?.handleStateSubscriptionError(error)
            }
        }
    }
}
