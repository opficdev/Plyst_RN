//
//  HomeSectionHeaderViewLike.swift
//  Plyst
//
//  Created by opfic on 10/1/26.
//

import UIKit

@MainActor
protocol HomeSectionHeaderViewLike: UICollectionReusableView, ReuseIdentifiable {
    func configure(title: String)
}
