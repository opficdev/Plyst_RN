//
//  HomeViewLike.swift
//  Plyst
//
//  Created by opfic on 10/1/26.
//

import UIKit

@MainActor
protocol HomeViewLike: UIView {
    var layout: HomeGridLayout { get }
    var textCellType: any (HomeTextCellLike & ClipCardLike).Type { get }
    var imageCellType: any (HomeImageCellLike & ClipCardLike).Type { get }
    var sectionHeaderType: any (HomeSectionHeaderViewLike & SectionTitleLike).Type { get }
    var pinnedRowType: any (HomePinnedRowViewLike & SectionTitleLike).Type { get }

    func reloadContent()
    func updateScrollPosition(_ offset: CGFloat)
    func snapHeader()
    func setSaving(_ isSaving: Bool)
    func setSelectedFilter(_ filter: HomeFilter)
    func setSearchButtonHidden(_ isHidden: Bool)
    func scrollToTop()

    func showEmptyState(
        title: String,
        message: String
    )

    func hideEmptyState()
}
