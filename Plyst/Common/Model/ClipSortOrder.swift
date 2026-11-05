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
        let times = clips.map { $0.createdAt.timeIntervalSinceReferenceDate.bitPattern.littleEndian }
        let order = clipSortOrder(
            createdAt: times.withUnsafeBytes { Data($0) },
            ids: ids
        )
        return order.withUnsafeBytes { bytes in
            stride(from: 0, to: bytes.count, by: MemoryLayout<UInt32>.size).map {
                clips[Int(UInt32(littleEndian: bytes.loadUnaligned(fromByteOffset: $0, as: UInt32.self)))]
            }
        }
    }
}
