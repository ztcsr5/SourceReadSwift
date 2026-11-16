//
//  Derived from VerticalContentOffsetPreservingLayout.swift, Aidoku (iOS).
//  Created by Skitty on 3/1/23. Thanks to Mantton.
//  SPDX-License-Identifier: GPL-3.0-only
//  Upstream revision: 95d1468d599a154f03d6a1dd06bf839d3ff3f7bd
//

import UIKit

/// Aidoku's identity-based offset preservation, adapted to recycled UIKit cells rather than Texture nodes.
final class ComicOffsetPreservingLayout: UICollectionViewLayout {
    struct ReadingLine {
        let key: ComicStripPageKey
        let fraction: CGFloat
    }

    var snapshot = ComicStripSnapshot()
    var heightForPage: ((ComicStripPageKey, CGFloat) -> CGFloat)?
    var footerHeight: CGFloat = 88
    private var attributes: [UICollectionViewLayoutAttributes] = []
    private var itemIdentifiers: [ComicStripPageKey] = []
    private var contentSize = CGSize.zero
    private var preservedViewportAnchor: ReadingLine?

    override var collectionViewContentSize: CGSize { contentSize }

    override func prepare() {
        super.prepare()
        guard let collectionView, collectionView.numberOfSections > 0 else { return }
        let width = max(collectionView.bounds.width, 1)
        itemIdentifiers = snapshot.pages.map(\.key)
        var origin: CGFloat = 0
        attributes = (0...itemIdentifiers.count).map { index in
            let attributes = UICollectionViewLayoutAttributes(forCellWith: IndexPath(item: index, section: 0))
            let height = index == itemIdentifiers.count ? footerHeight
                : (heightForPage?(itemIdentifiers[index], width) ?? 320)
            attributes.frame = CGRect(x: 0, y: origin, width: width, height: height)
            origin += height
            return attributes
        }
        contentSize = CGSize(width: width, height: origin)
    }

    override func shouldInvalidateLayout(forBoundsChange newBounds: CGRect) -> Bool {
        // A normal scroll reads the existing geometry, it never lays out a chapter again.
        collectionView?.bounds.width != newBounds.width
    }

    override func layoutAttributesForItem(at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        guard indexPath.section == 0, attributes.indices.contains(indexPath.item) else { return nil }
        return attributes[indexPath.item]
    }

    override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
        let first = firstItem(endingAfter: rect.minY)
        return Array(attributes.dropFirst(first).prefix { $0.frame.minY < rect.maxY })
    }

    func readingLine(at offset: CGFloat) -> ReadingLine? {
        guard !itemIdentifiers.isEmpty else { return nil }
        let line = max(offset, 0) + 0.5
        let index = min(firstItem(endingAfter: line), itemIdentifiers.count - 1)
        guard attributes.indices.contains(index) else { return nil }
        let frame = attributes[index].frame
        return ReadingLine(key: itemIdentifiers[index], fraction: min(max((offset - frame.minY) / frame.height, 0), 1))
    }

    func preserveVisiblePosition(_ anchor: ReadingLine?) { preservedViewportAnchor = anchor }
    func clearPreservedPosition() { preservedViewportAnchor = nil }

    override func targetContentOffset(forProposedContentOffset proposedContentOffset: CGPoint) -> CGPoint {
        preservedViewportAnchor.flatMap(contentOffset(for:)) ?? proposedContentOffset
    }

    /// Finds the new offset of the same point inside the same page, even after prepending or trimming a chapter.
    func contentOffset(for anchor: ReadingLine) -> CGPoint? {
        guard let collectionView, let index = snapshot.indices[anchor.key],
              let attributes = layoutAttributesForItem(at: IndexPath(item: index, section: 0)) else { return nil }
        let frame = attributes.frame
        let size = collectionView.bounds.size
        let inset = collectionView.adjustedContentInset
        let minimum = -inset.top
        let maximum = max(minimum, collectionViewContentSize.height - size.height + inset.bottom)
        return CGPoint(x: -inset.left, y: min(max(frame.minY + frame.height * anchor.fraction, minimum), maximum))
    }

    private func firstItem(endingAfter line: CGFloat) -> Int {
        var lower = 0
        var upper = attributes.count
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if attributes[middle].frame.maxY <= line { lower = middle + 1 }
            else { upper = middle }
        }
        return lower
    }
}
