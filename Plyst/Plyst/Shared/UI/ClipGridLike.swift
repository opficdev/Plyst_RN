//
//  ClipGridLike.swift
//  Plyst
//
//  Created by opfic on 10/3/26.
//

import UIKit

/// 클립 목록을 표시하는 컬렉션 뷰를 요구합니다.
@MainActor
protocol ClipGridLike: UIView {
    var collectionView: UICollectionView { get }
}
