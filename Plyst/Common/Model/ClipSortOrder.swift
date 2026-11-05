//
//  ClipSortOrder.swift
//  Plyst
//
//  Created by opfic on 9/28/26.
//

import Foundation
import PlystCore

enum ClipSortOrder: Equatable, Sendable {

    case createdAt

    /// 생성 시각의 내림차순으로 정렬
    /// 생성 시각이 같으면 식별자의 오름차순으로 순서를 결정
    func sorted(_ clips: [Clip]) -> [Clip] {
        var ids = Data(capacity: clips.count * MemoryLayout<uuid_t>.size)
        for clip in clips {
            withUnsafeBytes(of: clip.id.uuid) { ids.append(contentsOf: $0) }
        }
        return clipSortOrder(
            createdAt: clips.map { $0.createdAt.timeIntervalSinceReferenceDate },
            ids: ids
        ).map { clips[Int($0)] }
    }
}
