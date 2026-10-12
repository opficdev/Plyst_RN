//
//  Reactorable.swift
//  Plyst
//
//  Created by opfic on 9/28/26.
//

import ReactorKit
import RxSwift

/// Rx events are delivered on the main thread. This is not MainActor isolation.
protocol Reactorable: Reactor where Action: Sendable, Mutation: Sendable, State: Sendable {}

extension Reactorable {

    var scheduler: Scheduler {
        MainScheduler.instance
    }

    func transform(mutation: Observable<Mutation>) -> Observable<Mutation> {
        mutation.observe(on: MainScheduler.instance)
    }
}
