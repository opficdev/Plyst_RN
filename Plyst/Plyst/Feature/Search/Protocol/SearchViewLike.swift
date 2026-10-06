//
//  SearchViewLike.swift
//  Plyst
//
//  Created by opfic on 10/1/26.
//

import UIKit

@MainActor
protocol SearchViewLike: UIView {
    var layout: HomeGridLayout { get }
    var textCellType: any (HomeTextCellLike & ClipCardLike).Type { get }
    var imageCellType: any (HomeImageCellLike & ClipCardLike).Type { get }
    var sectionHeaderType: any (HomeSectionHeaderViewLike & SectionTitleLike).Type { get }

    func focusSearchField()
    func expand()
    func collapse(completion: @escaping @MainActor () -> Void)
    func setQuery(_ query: String)
    func setSelectedFilter(_ filter: HomeFilter)
    func reloadContent()
    func scrollToTop()

    func setRecent(
        terms: [String],
        message: String?,
        showsClear: Bool
    )

    func showRecent()
    func showResults()

    func showEmptyState(
        title: String,
        message: String
    )
}
