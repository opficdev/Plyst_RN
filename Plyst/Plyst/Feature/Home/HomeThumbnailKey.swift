//
//  HomeThumbnailKey.swift
//  Plyst
//
//  Created by opfic on 10/10/26.
//

import Foundation

struct HomeThumbnailKey: Hashable, Sendable {
    let clipID: Clip.ID
    let fileID: UUID
    let maximumPixelDimension: Int
}
