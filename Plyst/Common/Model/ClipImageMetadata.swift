//
//  ClipImageMetadata.swift
//  Plyst
//
//  Created by opfic on 9/28/26.
//

import Foundation

struct ClipImageMetadata: Equatable, Sendable {

    /// 이미지 파일 서비스에서 해석하는 불투명 식별자입니다. 경로나 파일 이름을 나타내지 않습니다.
    let fileID: UUID
    /// public.png와 같은 통일된 타입 식별자입니다.
    let contentType: String
    let pixelWidth: Int
    let pixelHeight: Int
    let byteCount: Int

    var isValid: Bool {
        !contentType.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && 0 < pixelWidth
            && 0 < pixelHeight
            && 0 < byteCount
    }
}
