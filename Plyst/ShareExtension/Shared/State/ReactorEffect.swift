//
//  ReactorEffect.swift
//  Plyst
//
//  Created by opfic on 9/28/26.
//

import RxSwift

enum ReactorEffect {
    /// Reactor가 해제될 때 요청을 취소할 수 있도록 서비스만 캡처합니다.
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
}
