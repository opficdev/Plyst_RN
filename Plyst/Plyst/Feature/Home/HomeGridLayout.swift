//
//  HomeGridLayout.swift
//  Plyst
//
//  Created by opfic on 9/30/26.
//

import UIKit

@MainActor
protocol HomeGridLayoutDelegate: AnyObject {
    func homeLayout(
        _ layout: HomeGridLayout,
        heightForItemAt indexPath: IndexPath,
        width: CGFloat
    ) -> CGFloat

    func homeLayoutHeightForPinnedRow(_ layout: HomeGridLayout) -> CGFloat
}

extension HomeGridLayoutDelegate {
    /// 상단 고정 행이 없는 화면은 높이를 구현하지 않아도 되도록 0을 기본값으로 둡니다.
    func homeLayoutHeightForPinnedRow(_ layout: HomeGridLayout) -> CGFloat {
        0
    }
}

final class HomeGridLayout: UICollectionViewLayout {
    static let headerKind = "HomeSectionHeader"
    static let pinnedRowKind = "HomePinnedRow"
    private static let pinnedRowIndexPath = IndexPath(item: 0, section: 0)

    weak var delegate: HomeGridLayoutDelegate?

    private var items = [IndexPath: UICollectionViewLayoutAttributes]()
    private var headers = [IndexPath: UICollectionViewLayoutAttributes]()
    private var pinnedRow: UICollectionViewLayoutAttributes?
    private var contentHeight = CGFloat.zero

    override func prepare() {
        super.prepare()
        guard let collectionView else { return }
        items.removeAll(keepingCapacity: true)
        headers.removeAll(keepingCapacity: true)
        pinnedRow = nil

        let width = collectionView.bounds.width
        let columnWidth = max(1, (width - 42) / 2)
        var verticalOffset = CGFloat.zero

        let pinnedRowHeight = delegate?.homeLayoutHeightForPinnedRow(self) ?? 0
        // 상단 고정 항목이 있으면 section 0을 그 전용으로 두고 시간순 구간은 section 1부터 시작한다.
        let firstTimelineSection = 0 < pinnedRowHeight ? 1 : 0
        if 0 < pinnedRowHeight {
            let attributes = UICollectionViewLayoutAttributes(
                forSupplementaryViewOfKind: Self.pinnedRowKind,
                with: Self.pinnedRowIndexPath
            )
            attributes.frame = CGRect(
                x: 0,
                y: 0,
                width: width,
                height: pinnedRowHeight
            )
            pinnedRow = attributes
            verticalOffset = pinnedRowHeight
        }

        for section in 0..<collectionView.numberOfSections where firstTimelineSection <= section {
            let headerPath = IndexPath(item: 0, section: section)
            let header = UICollectionViewLayoutAttributes(
                forSupplementaryViewOfKind: Self.headerKind,
                with: headerPath
            )
            let headerHeight = CGFloat(44)
            header.frame = CGRect(x: 0, y: verticalOffset, width: width, height: headerHeight)
            headers[headerPath] = header
            verticalOffset += headerHeight

            var columnHeights = [verticalOffset, verticalOffset]
            for item in 0..<collectionView.numberOfItems(inSection: section) {
                let indexPath = IndexPath(item: item, section: section)
                let column = columnHeights[0] <= columnHeights[1] ? 0 : 1
                let horizontalOffset = 16 + CGFloat(column) * (columnWidth + 10)
                let height = delegate?.homeLayout(self, heightForItemAt: indexPath, width: columnWidth) ?? 0
                let attributes = UICollectionViewLayoutAttributes(forCellWith: indexPath)
                attributes.frame = CGRect(x: horizontalOffset, y: columnHeights[column], width: columnWidth, height: height)
                items[indexPath] = attributes
                columnHeights[column] += height + 10
            }
            if 0 < collectionView.numberOfItems(inSection: section) {
                verticalOffset = max(columnHeights[0], columnHeights[1]) + 10
            }
        }
        contentHeight = verticalOffset
    }

    override var collectionViewContentSize: CGSize {
        guard let collectionView else { return .zero }
        return CGSize(
            width: collectionView.bounds.width,
            height: max(contentHeight, collectionView.bounds.height)
        )
    }

    override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
        let visiblePinnedRow = pinnedRow.map { $0.frame.intersects(rect) ? [$0] : [] } ?? []
        let visibleHeaders = headers.values.filter { $0.frame.intersects(rect) }
        let visibleItems = items.values.filter { $0.frame.intersects(rect) }
        return visiblePinnedRow + visibleHeaders + visibleItems
    }

    override func layoutAttributesForItem(at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        items[indexPath]
    }

    override func layoutAttributesForSupplementaryView(
        ofKind elementKind: String,
        at indexPath: IndexPath
    ) -> UICollectionViewLayoutAttributes? {
        switch elementKind {
        case Self.headerKind: headers[indexPath]
        case Self.pinnedRowKind: pinnedRow
        default: nil
        }
    }

    override func shouldInvalidateLayout(forBoundsChange newBounds: CGRect) -> Bool {
        guard let collectionView else { return false }
        return collectionView.bounds.width != newBounds.width
    }
}
