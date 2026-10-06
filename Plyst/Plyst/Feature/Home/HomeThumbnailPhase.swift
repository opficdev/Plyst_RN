//
//  HomeThumbnailPhase.swift
//  Plyst
//
//  Created by opfic on 10/3/26.
//

import UIKit

/// 이미지 클립 카드가 그릴 썸네일의 상태입니다. ViewController가 State에서 판정해 View로 전달하며 Reactor State에는 담지 않습니다.
enum HomeThumbnailPhase {
    /// 아직 불러오는 중이거나 요청 전입니다.
    case pending
    case loaded(UIImage)
    /// 불러오지 못했거나 디코딩하지 못했습니다.
    case failed

    var image: UIImage? {
        guard case .loaded(let image) = self else { return nil }
        return image
    }

    var isPending: Bool {
        guard case .pending = self else { return false }
        return true
    }

    var isFailed: Bool {
        guard case .failed = self else { return false }
        return true
    }
}
