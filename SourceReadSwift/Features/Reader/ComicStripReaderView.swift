import SwiftUI
import UIKit

/// Recycles real page cells. Only stable layout changes are applied during a gesture.
struct ComicStripReaderView: UIViewRepresentable {
    var snapshot: ComicStripSnapshot
    let contentKey: Int
    let viewport: CGSize
    let chapterOffset: Int
    var targetPage: Int?
    var targetFraction: Double
    let footer: Footer
    let display: ComicDisplayOptions
    let reducesMotion: Bool
    let isContinuous: Bool
    var onTargetApplied: () -> Void
    let onTap: () -> Void
    let onRefreshAddresses: (Int) -> Void
    let onPosition: (ComicStripPageKey, ComicPageAnchor, Bool) -> Void
    let onApproachChapter: (Int) -> Void
    let onBeginDragging: () -> Void

    struct Footer {
        let title: String
        let isEnabled: Bool
        let action: () -> Void
    }

    func makeCoordinator() -> Coordinator { Coordinator(view: self) }

    func makeUIView(context: Context) -> UICollectionView {
        let strip = UICollectionView(frame: .zero, collectionViewLayout: ComicOffsetPreservingLayout())
        strip.contentInsetAdjustmentBehavior = .never
        strip.decelerationRate = .normal
        strip.alwaysBounceVertical = true
        strip.accessibilityIdentifier = "comic.stripSurface"
        context.coordinator.attach(to: strip)
        return strip
    }

    func updateUIView(_ strip: UICollectionView, context: Context) { context.coordinator.update(self) }

    static func dismantleUIView(_ strip: UICollectionView, coordinator: Coordinator) {
        coordinator.cancelLoads()
        strip.delegate = nil
        strip.dataSource = nil
    }
}

extension ComicStripReaderView {
    @MainActor final class Coordinator: NSObject, UICollectionViewDataSource, UICollectionViewDelegate {
        private struct Load {
            let id: UUID
            let task: Task<Void, Never>
        }

        private var view: ComicStripReaderView
        private var snapshot: ComicStripSnapshot
        weak var strip: UICollectionView?
        private var layout: ComicOffsetPreservingLayout? { strip?.collectionViewLayout as? ComicOffsetPreservingLayout }
        private var sizes: [ComicStripPageKey: CGSize] = [:]
        private var pendingSizes: [ComicStripPageKey: CGSize] = [:]
        private var failures: [ComicStripPageKey: ComicImageFailure] = [:]
        private var loads: [ComicStripPageKey: Load] = [:]
        private var visibleBitmaps: [ComicStripPageKey: UIImage] = [:]
        private var geometryRefresh: Task<Void, Never>?
        private var reportedPage: ComicStripPageKey?
        private var appliedTarget: ComicStripPageKey?
        private var pendingTarget: ComicOffsetPreservingLayout.ReadingLine?
        private var isRestoringAnchor = false
        private var isReplacingSnapshot = false
        private var zoomedPage: ComicStripPageKey?
        private var requestedEdges: Set<Int> = []
        private(set) var deferredSizeCount = 0

        private var isInteracting: Bool {
            guard let strip else { return false }
            return zoomedPage != nil || strip.isDragging || strip.isDecelerating || strip.isTracking
        }

        init(view: ComicStripReaderView) {
            self.view = view
            snapshot = view.snapshot
        }

        func attach(to strip: UICollectionView) {
            self.strip = strip
            layout?.snapshot = snapshot
            layout?.heightForPage = { [weak self] page, width in
                guard let self else { return 320 }
                let ratio = self.view.display.artworkRatio(viewport: self.view.viewport)
                return ComicStripGeometry.height(for: self.sizes[page], width: width * ratio)
            }
            strip.backgroundColor = view.display.canvas.color
            strip.register(ComicStripImageCell.self, forCellWithReuseIdentifier: "page")
            strip.register(ComicStripFooterCell.self, forCellWithReuseIdentifier: "footer")
            strip.dataSource = self
            strip.delegate = self
        }

        func update(_ next: ComicStripReaderView) {
            guard let strip else { return }
            let needsReset = view.contentKey != next.contentKey
            let renderOptionsChanged = view.display != next.display || view.reducesMotion != next.reducesMotion
            let didChangeGeometry = view.viewport != next.viewport
                || view.display.artworkRatio(viewport: view.viewport) != next.display.artworkRatio(viewport: next.viewport)
            let qualityChanged = view.display.maxImagePixels != next.display.maxImagePixels
            let anchor = didChangeGeometry ? pendingTarget ?? captureReadingLine() : nil
            if next.isContinuous != view.isContinuous { requestedEdges.removeAll() }
            view = next
            strip.backgroundColor = next.display.canvas.color
            if needsReset {
                reset(to: next.snapshot)
            } else if snapshot.revision != next.snapshot.revision, !isInteracting {
                replaceSnapshot(next.snapshot)
            }
            if didChangeGeometry, !needsReset { refreshGeometry(around: anchor) }
            if qualityChanged {
                cancelLoads()
                failures.removeAll()
                visibleBitmaps.removeAll()
            }
            if renderOptionsChanged {
                displayReadyImages(loadMissing: qualityChanged)
                reportedPage = nil
            }
            configureFooter()
            applyRequestedTarget()
        }

        private func reset(to next: ComicStripSnapshot) {
            guard let strip else { return }
            cancelLoads()
            sizes.removeAll()
            visibleBitmaps.removeAll()
            failures.removeAll()
            pendingSizes.removeAll()
            requestedEdges.removeAll()
            appliedTarget = nil
            pendingTarget = nil
            reportedPage = nil
            zoomedPage = nil
            strip.isScrollEnabled = true
            isRestoringAnchor = true
            snapshot = next
            layout?.snapshot = next
            layout?.invalidateLayout()
            strip.reloadData()
            isRestoringAnchor = false
        }

        private func replaceSnapshot(_ next: ComicStripSnapshot) {
            guard let strip, let layout, !isReplacingSnapshot else { return }
            let previous = snapshot
            let anchor = pendingTarget ?? captureReadingLine()
            let removed = previous.pages.enumerated().compactMap { index, page in
                next.indices[page.key] == nil ? IndexPath(item: index, section: 0) : nil
            }
            let inserted = next.pages.enumerated().compactMap { index, page in
                previous.indices[page.key] == nil ? IndexPath(item: index, section: 0) : nil
            }
            guard !previous.pages.isEmpty, !next.pages.isEmpty else {
                reset(to: next)
                return
            }
            let mounted = Set(next.pages.map { $0.key.chapterOffset })
            requestedEdges.subtract(mounted)
            for key in Array(loads.keys) where next.indices[key] == nil { cancelLoad(key) }
            sizes = sizes.filter { next.indices[$0.key] != nil }
            pendingSizes = pendingSizes.filter { next.indices[$0.key] != nil }
            failures = failures.filter { next.indices[$0.key] != nil }
            visibleBitmaps = visibleBitmaps.filter { next.indices[$0.key] != nil }
            isReplacingSnapshot = true
            isRestoringAnchor = true
            layout.preserveVisiblePosition(anchor)
            UIView.performWithoutAnimation {
                strip.performBatchUpdates {
                    self.snapshot = next
                    layout.snapshot = next
                    strip.deleteItems(at: removed)
                    strip.insertItems(at: inserted)
                    layout.invalidateLayout()
                } completion: { [weak self] _ in
                    DispatchQueue.main.async {
                        guard let self else { return }
                        self.isReplacingSnapshot = false
                        self.applyStagedChanges()
                        self.reportReadingLine()
                    }
                }
                strip.layoutIfNeeded()
                restoreReadingLine(anchor)
            }
            layout.clearPreservedPosition()
            isRestoringAnchor = false
        }

        private func applyRequestedTarget() {
            guard let page = view.targetPage else {
                appliedTarget = nil
                if let target = pendingTarget, sizes[target.key] != nil {
                    pendingTarget = nil
                    DispatchQueue.main.async { [weak self] in self?.reportReadingLine() }
                }
                return
            }
            let key = ComicStripPageKey(chapterOffset: view.chapterOffset, pageIndex: page)
            guard appliedTarget != key, snapshot.indices[key] != nil else { return }
            appliedTarget = key
            let anchor = ComicOffsetPreservingLayout.ReadingLine(
                key: key, fraction: CGFloat(ComicPageAnchor(pageIndex: page, fraction: view.targetFraction).fraction))
            pendingTarget = anchor
            let contentKey = view.contentKey
            DispatchQueue.main.async { [weak self] in
                guard let self, self.view.contentKey == contentKey, self.appliedTarget == key,
                      self.pendingTarget?.key == key, self.view.targetPage == page else { return }
                self.isRestoringAnchor = true
                self.strip?.layoutIfNeeded()
                self.restoreReadingLine(anchor)
                self.isRestoringAnchor = false
                if self.sizes[key] != nil { self.pendingTarget = nil }
                self.view.onTargetApplied()
                self.beginLoad(key)
                self.reportReadingLine()
            }
        }

        func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
            snapshot.pages.count + 1
        }

        func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
            if indexPath.item == snapshot.pages.count {
                let footer = collectionView.dequeueReusableCell(withReuseIdentifier: "footer", for: indexPath) as! ComicStripFooterCell
                configure(footer)
                return footer
            }
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "page", for: indexPath) as! ComicStripImageCell
            configure(cell, page: snapshot.pages[indexPath.item])
            return cell
        }

        func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
            guard snapshot.pages.indices.contains(indexPath.item) else { return }
            let key = snapshot.pages[indexPath.item].key
            DispatchQueue.main.async { [weak self] in self?.beginLoad(key) }
        }

        func collectionView(_ collectionView: UICollectionView, didEndDisplaying cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
            if let key = (cell as? ComicStripImageCell)?.pageKey { visibleBitmaps.removeValue(forKey: key) }
        }

        private func configureFooter() {
            if let footer = strip?.cellForItem(at: IndexPath(item: snapshot.pages.count, section: 0)) as? ComicStripFooterCell {
                configure(footer)
            }
        }

        private func configure(_ cell: ComicStripFooterCell) {
            cell.configure(title: view.footer.title, isEnabled: view.footer.isEnabled, ink: view.display.canvas.ink, action: view.footer.action)
        }

        private func configure(_ cell: ComicStripImageCell, page: ComicStripPage) {
            let key = page.key
            // Showing an image inside its estimated frame causes the fit-size "bounce" on first decode.
            let image = sizes[key] != nil ? visibleBitmaps[key] ?? cachedImage(page) : nil
            cell.configure(image: image, key: key, failure: failures[key], display: view.display,
                artworkRatio: view.display.artworkRatio(viewport: view.viewport), reducesMotion: view.reducesMotion)
            cell.onTap = view.onTap
            cell.onRefreshAddresses = { [weak self] in self?.view.onRefreshAddresses(key.chapterOffset) }
            cell.onRetry = { [weak self] in
                guard let self else { return }
                self.failures.removeValue(forKey: key)
                self.updateCell(key)
                self.beginLoad(key)
            }
            cell.onZoomChanged = { [weak self] isZoomed in
                guard let self else { return }
                if isZoomed, self.zoomedPage != key { self.zoomedPage = key }
                else if !isZoomed, self.zoomedPage == key { self.zoomedPage = nil }
                else { return }
                self.strip?.isScrollEnabled = !isZoomed
                if !isZoomed { self.settlePosition() }
            }
        }

        private func cachedImage(_ page: ComicStripPage) -> UIImage? {
            guard let url = URL(string: page.request.url) else { return nil }
            return RemoteImageLoader.shared.cachedComicPage(for: url, headers: page.request.headers, maxPixelSize: view.display.maxImagePixels)
        }

        private func updateCell(_ key: ComicStripPageKey) {
            guard let index = snapshot.indices[key],
                  let cell = strip?.cellForItem(at: IndexPath(item: index, section: 0)) as? ComicStripImageCell else { return }
            configure(cell, page: snapshot.pages[index])
        }

        private func displayReadyImages(loadMissing: Bool = false) {
            for index in strip?.indexPathsForVisibleItems ?? [] where snapshot.pages.indices.contains(index.item) {
                let key = snapshot.pages[index.item].key
                updateCell(key)
                if loadMissing { beginLoad(key) }
            }
        }

        func cancelLoads() {
            geometryRefresh?.cancel()
            geometryRefresh = nil
            for key in Array(loads.keys) { cancelLoad(key) }
        }

        private func cancelLoad(_ key: ComicStripPageKey) { loads.removeValue(forKey: key)?.task.cancel() }

        private func beginLoad(_ key: ComicStripPageKey) {
            guard loads[key] == nil, failures[key] == nil, let index = snapshot.indices[key] else { return }
            let page = snapshot.pages[index]
            if let image = visibleBitmaps[key] ?? cachedImage(page) {
                if isVisible(key) { visibleBitmaps[key] = image }
                if sizes[key] == image.size { updateCell(key) }
                else { acceptSize(image.size, for: key) }
                return
            }
            guard let url = URL(string: page.request.url) else { failures[key] = .invalidResponse; updateCell(key); return }
            let id = UUID()
            let maxPixels = view.display.maxImagePixels
            let task = Task { @MainActor [weak self] in
                let result = await RemoteImageLoader.shared.comicPage(for: url, headers: page.request.headers, maxPixelSize: maxPixels)
                guard let self, self.loads[key]?.id == id else { return }
                self.loads.removeValue(forKey: key)
                guard !Task.isCancelled, self.snapshot.indices[key] != nil, self.view.display.maxImagePixels == maxPixels else { return }
                switch result {
                case .success(let image):
                    // NSCache may evict a tall strip immediately. A page on screen must not depend on that cache hit.
                    if self.isVisible(key) { self.visibleBitmaps[key] = image }
                    if self.sizes[key] == image.size { self.updateCell(key) }
                    else { self.acceptSize(image.size, for: key) }
                case .failure(.cancelled):
                    if self.isVisible(key) { self.beginLoad(key) }
                case .failure(let failure):
                    self.failures[key] = failure
                    self.updateCell(key)
                }
            }
            loads[key] = Load(id: id, task: task)
        }

        private func isVisible(_ key: ComicStripPageKey) -> Bool {
            guard let index = snapshot.indices[key] else { return false }
            return strip?.indexPathsForVisibleItems.contains(IndexPath(item: index, section: 0)) == true
        }

        func acceptSize(_ size: CGSize, for index: Int) {
            guard snapshot.pages.indices.contains(index) else { return }
            acceptSize(size, for: snapshot.pages[index].key)
            // Exercise the same coalesced queue deterministically in geometry tests.
            if !isInteracting { applyStagedChanges() }
        }

        private func acceptSize(_ size: CGSize, for key: ComicStripPageKey) {
            guard let index = snapshot.indices[key], size.width > 0, size.height > 0,
                  size.width.isFinite, size.height.isFinite, sizes[key] != size, pendingSizes[key] != size else { return }
            pendingSizes[key] = size
            let lastVisible = strip?.indexPathsForVisibleItems.map(\.item).max() ?? 0
            if isInteracting && index <= lastVisible { deferredSizeCount += 1 }
            guard geometryRefresh == nil, !isInteracting else { return }
            geometryRefresh = Task { @MainActor [weak self] in
                await Task.yield()
                guard !Task.isCancelled, let self else { return }
                self.geometryRefresh = nil
                self.applyStagedChanges()
                self.reportReadingLine()
            }
        }

        private func applyStagedChanges() {
            guard !isInteracting, !isReplacingSnapshot, !isRestoringAnchor else { return }
            if snapshot.revision != view.snapshot.revision { replaceSnapshot(view.snapshot) }
            guard !pendingSizes.isEmpty else { return }
            let anchor = pendingTarget ?? captureReadingLine()
            sizes.merge(pendingSizes, uniquingKeysWith: { _, latest in latest })
            pendingSizes.removeAll()
            refreshGeometry(around: anchor)
            if let target = pendingTarget, sizes[target.key] != nil, view.targetPage == nil { pendingTarget = nil }
            displayReadyImages(loadMissing: true)
        }

        private func refreshGeometry(around anchor: ComicOffsetPreservingLayout.ReadingLine?) {
            guard let strip, let layout else { return }
            let wasRestoring = isRestoringAnchor
            isRestoringAnchor = true
            layout.invalidateLayout()
            strip.layoutIfNeeded()
            restoreReadingLine(anchor)
            isRestoringAnchor = wasRestoring
        }

        private func captureReadingLine() -> ComicOffsetPreservingLayout.ReadingLine? {
            guard let strip else { return nil }
            return layout?.readingLine(at: strip.contentOffset.y)
        }

        private func restoreReadingLine(_ anchor: ComicOffsetPreservingLayout.ReadingLine?) {
            guard let strip, let anchor, let offset = layout?.contentOffset(for: anchor),
                  abs(offset.y - strip.contentOffset.y) > 0.5 else { return }
            strip.setContentOffset(offset, animated: false)
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) { reportReadingLine() }

        func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
            pendingTarget = nil
            view.onTargetApplied()
            view.onBeginDragging()
        }

        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
            if !decelerate { settlePosition() }
        }

        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) { settlePosition() }
        func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) { settlePosition() }

        private func settlePosition() {
            applyStagedChanges()
            reportReadingLine(isSettled: true)
        }

        private func reportReadingLine(isSettled: Bool = false) {
            guard !isRestoringAnchor, zoomedPage == nil, let strip,
                  let anchor = pendingTarget ?? captureReadingLine(), let index = snapshot.indices[anchor.key] else { return }
            let page = ComicPageAnchor(pageIndex: anchor.key.pageIndex, fraction: Double(anchor.fraction))
            if sizes[anchor.key] != nil {
                let value = "第 \(page.pageIndex + 1) 页 · \(Int(page.fraction * 100))%"
                if strip.accessibilityValue != value { strip.accessibilityValue = value }
            }
            guard pendingTarget == nil || isSettled else { return }
            view.onPosition(anchor.key, page, isSettled)
            if reportedPage != anchor.key {
                let movesUp = index < (reportedPage.flatMap { snapshot.indices[$0] } ?? index)
                reportedPage = anchor.key
                updatePrefetch(around: index, direction: movesUp ? -1 : 1)
            }
            checkInfiniteLoad()
        }

        private func updatePrefetch(around index: Int, direction: Int) {
            let offsets = ComicPagePositionPolicy.prefetchOrder(around: index, count: snapshot.pages.count,
                direction: direction, depth: view.display.preloadPages)
            let keys = offsets.map { snapshot.pages[$0].key }
            let keep = Set(keys)
            for key in Array(loads.keys) where !keep.contains(key) && !isVisible(key) { cancelLoad(key) }
            beginLoad(snapshot.pages[index].key)
            guard !ProcessInfo.processInfo.isLowPowerModeEnabled, ProcessInfo.processInfo.thermalState.rawValue < 2 else { return }
            for key in keys { beginLoad(key) }
        }

        private func checkInfiniteLoad() {
            guard view.isContinuous, let strip, let layout,
                  let first = snapshot.pages.first?.key, let last = snapshot.pages.last?.key else { return }
            let top = layout.readingLine(at: strip.contentOffset.y)?.key
            let bottom = layout.readingLine(at: strip.contentOffset.y + strip.bounds.height)?.key
            if top == first { requestEdge(first.chapterOffset - 1) }
            let preload = min(max(view.display.preloadPages, 0), ComicDisplayOptions.maximumPrefetchPages)
            if let top, top.chapterOffset == last.chapterOffset, let bottom, bottom.chapterOffset == last.chapterOffset,
               last.pageIndex - bottom.pageIndex <= preload {
                requestEdge(last.chapterOffset + 1)
            }
        }

        private func requestEdge(_ offset: Int) {
            guard offset >= 0, requestedEdges.insert(offset).inserted else { return }
            let contentKey = view.contentKey
            DispatchQueue.main.async { [weak self] in
                guard let self, self.view.contentKey == contentKey, self.view.isContinuous else { return }
                self.view.onApproachChapter(offset)
            }
        }
    }
}
enum ComicStripGeometry {
    static func height(for imageSize: CGSize?, width: CGFloat) -> CGFloat {
        guard let imageSize, imageSize.width > 0, imageSize.height > 0,
              imageSize.width.isFinite, imageSize.height.isFinite else { return 320 }
        return max(1, max(width, 1) * imageSize.height / imageSize.width)
    }
}
