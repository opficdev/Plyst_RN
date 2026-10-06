//
//  FeedbackPresentable.swift
//  Plyst
//
//  Created by opfic on 10/1/26.
//

import Foundation

/// 토스트로 표시할 피드백입니다. 같은 id는 같은 피드백으로 보고 한 번만 표시합니다.
protocol FeedbackPresentable: Sendable {
    var id: UUID { get }
    var message: String { get }
    var isSuccess: Bool { get }
}
