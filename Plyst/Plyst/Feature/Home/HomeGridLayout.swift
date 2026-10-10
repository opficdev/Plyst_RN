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
}

final class HomeGridLayout: UICollectionViewLayout {
    static let headerKind = "HomeSectionHeader"

    weak var delegate: HomeGridLayoutDelegate?

    private var items = [IndexPath: UICollectionViewLayoutAttributes]()
    private var headers = [IndexPath: UICollectionViewLayoutAttributes]()
    private var contentHeight = CGFloat.zero

    override func prepare() {
        super.prepare()
        guard let collectionView else { return }
        items.removeAll(keepingCapacity: true)
        headers.removeAll(keepingCapacity: true)

        let width = collectionView.bounds.width
        let columnWidth = max(1, (width - 42) / 2)
        var verticalOffset = CGFloat.zero

        for section in 0..<collectionView.numberOfSections {
            let headerPath = IndexPath(item: 0, section: section)
            let header = UICollectionViewLayoutAttributes(
                forSupplementaryViewOfKind: Self.headerKind,
                with: headerPath
            )
            let headerHeight = CGFloat(44)
            header.frame = CGRect(
                x: 0,
                y: verticalOffset,
                width: width,
                height: headerHeight
            )
            headers[headerPath] = header
            verticalOffset += headerHeight

            var columnHeights = [verticalOffset, verticalOffset]
            for item in 0..<collectionView.numberOfItems(inSection: section) {
                let indexPath = IndexPath(item: item, section: section)
                let column = columnHeights[0] <= columnHeights[1] ? 0 : 1
                let horizontalOffset = 16 + CGFloat(column) * (columnWidth + 10)
                let height = delegate?.homeLayout(self, heightForItemAt: indexPath, width: columnWidth) ?? 0
                let attributes = UICollectionViewLayoutAttributes(forCellWith: indexPath)
                attributes.frame = CGRect(
                    x: horizontalOffset,
                    y: columnHeights[column],
                    width: columnWidth,
                    height: height
                )
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
        let visibleHeaders = headers.values.filter { $0.frame.intersects(rect) }
        let visibleItems = items.values.filter { $0.frame.intersects(rect) }
        return visibleHeaders + visibleItems
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
        default: nil
        }
    }

    override func shouldInvalidateLayout(forBoundsChange newBounds: CGRect) -> Bool {
        guard let collectionView else { return false }
        return collectionView.bounds.width != newBounds.width
    }
}
