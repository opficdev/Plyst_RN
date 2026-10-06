//
//  ThumbnailImageCache+HomeThumbnailKey.swift
//  Plyst
//
//  Created by opfic on 10/1/26.
//

import UIKit

extension ThumbnailImageCache {
    func image(
        for key: HomeThumbnailKey,
        data: Data?
    ) -> UIImage? {
        image(
            fileID: key.fileID,
            maximumPixelDimension: key.maximumPixelDimension,
            data: data
        )
    }

    /// 이미지가 있으면 loaded입니다. 불러오기에 실패했거나 받은 data를 디코딩하지 못하면 failed이고 그 외에는 pending입니다.
    func phase(
        for key: HomeThumbnailKey,
        data: Data?,
        didFail: Bool
    ) -> HomeThumbnailPhase {
        if let image = image(for: key, data: data) { return .loaded(image) }
        return didFail || data != nil ? .failed : .pending
    }

    /// State의 썸네일 data와 실패 집합에서 key의 상태를 판정합니다.
    func phase(
        for key: HomeThumbnailKey,
        data: [HomeThumbnailKey: Data],
        failed: Set<HomeThumbnailKey>
    ) -> HomeThumbnailPhase {
        phase(
            for: key,
            data: data[key],
            didFail: failed.contains(key)
        )
    }
}
