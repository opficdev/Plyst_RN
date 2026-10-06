//
//  ThumbnailImageCache.swift
//  Plyst
//
//  Created by opfic on 10/1/26.
//

import UIKit

/// 디코딩한 썸네일 이미지를 개수 제한 안에서 보관합니다.
/// 같은 파일과 같은 크기의 이미지는 다시 디코딩하지 않습니다.
@MainActor
final class ThumbnailImageCache {
    private let cache = NSCache<NSString, UIImage>()

    init(countLimit: Int) {
        cache.countLimit = countLimit
    }

    /// 보관 중인 이미지가 있으면 그대로 반환합니다. 없으면 data를 디코딩해 보관한 뒤 반환합니다.
    func image(
        fileID: UUID,
        maximumPixelDimension: Int,
        data: Data?
    ) -> UIImage? {
        let cacheKey = "\(fileID.uuidString)-\(maximumPixelDimension)" as NSString
        if let image = cache.object(forKey: cacheKey) { return image }
        guard let data, let image = UIImage(data: data) else { return nil }
        cache.setObject(image, forKey: cacheKey)
        return image
    }
}
