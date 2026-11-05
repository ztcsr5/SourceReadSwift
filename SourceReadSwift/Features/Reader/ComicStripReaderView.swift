import SwiftUI
import UIKit

/// A recycled native strip; asynchronous image sizes never interrupt an active drag.
struct ComicStripReaderView: UIViewRepresentable {
    let requests: [ComicImageRequest]
    let contentKey: String
    let viewportWidth: CGFloat
    var targetPage: Int?
    let footerTitle: String
    let canActivateFooter: Bool
    let reducesMotion: Bool
    let onVisiblePage: (Int) -> Void
    var onTargetApplied: () -> Void
    let onTap: () -> Void
    let onRefreshAddresses: () -> Void
    let onFooter: () -> Void
    var targetFraction: Double = 0
    var onPosition: (ComicPageAnchor, Bool) -> Void = { _, _ in }

    func makeCoordinator() -> Coordinator { Coordinator(view: self) }

    func makeUIView(context: Context) -> UICollectionView {
        let layout = UICollectionViewFlowLayout()
        layout.minimumLineSpacing = 0
        layout.minimumInteritemSpacing = 0
        let strip = UICollectionView(frame: .zero, collectionViewLayout: layout)
        strip.backgroundColor = .black
        strip.contentInsetAdjustmentBehavior = .never
        strip.decelerationRate = .normal
        strip.alwaysBounceVertical = true
        strip.dataSource = context.coordinator
        strip.delegate = context.coordinator
        strip.register(ComicStripImageCell.self, forCellWithReuseIdentifier: "page")
        strip.register(ComicStripFooterCell.self, forCellWithReuseIdentifier: "footer")
        strip.accessibilityIdentifier = "comic.stripSurface"
        context.coordinator.strip = strip
        return strip
    }

    func updateUIView(_ strip: UICollectionView, context: Context) {
        context.coordinator.update(self)
    }

    static func dismantleUIView(_ strip: UICollectionView, coordinator: Coordinator) {
        coordinator.cancelLoads()
        strip.delegate = nil
        strip.dataSource = nil
    }

    @MainActor final class Coordinator: NSObject, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
        private struct Load {
            let id: UUID
            let task: Task<Void, Never>
        }
        private struct Anchor {
            let index: Int
            let fraction: CGFloat
        }
        private var view: ComicStripReaderView
        weak var strip: UICollectionView?
        private var sizes: [Int: CGSize] = [:]
        private var pendingSizes: [Int: CGSize] = [:]
        private var failures: [Int: ComicImageFailure] = [:]
        private var loads: [Int: Load] = [:]
        private var generation = UUID()
        private var reportedPage = -1
        private var appliedTarget: Int?
        private var pendingTargetAnchor: Anchor?
        private var isRestoringAnchor = false
        private var zoomedPage: Int?
        private var isZooming: Bool { zoomedPage != nil }
        private(set) var deferredSizeCount = 0

        init(view: ComicStripReaderView) { self.view = view }

        func update(_ next: ComicStripReaderView) {
            guard let strip else { return }
            let didChangeChapter = view.contentKey != next.contentKey || view.requests != next.requests
            let didChangeWidth = view.viewportWidth != next.viewportWidth
            let anchor = didChangeWidth ? pendingTargetAnchor ?? captureAnchor() : nil
            view = next
            if didChangeChapter {
                cancelLoads()
                generation = UUID()
                sizes.removeAll()
                pendingSizes.removeAll()
                failures.removeAll()
                appliedTarget = nil
                pendingTargetAnchor = nil
                reportedPage = -1
                zoomedPage = nil
                strip.isScrollEnabled = true
                strip.reloadData()
            } else if didChangeWidth {
                refreshGeometry(around: anchor)
            }
            if let footer = strip.cellForItem(at: IndexPath(item: next.requests.count, section: 0)) as? ComicStripFooterCell {
                footer.configure(title: next.footerTitle, isEnabled: next.canActivateFooter, action: next.onFooter)
            }
            if next.targetPage == nil { appliedTarget = nil }
            if let target = next.targetPage, target != appliedTarget, next.requests.indices.contains(target) {
                appliedTarget = target
                pendingTargetAnchor = Anchor(index: target, fraction: CGFloat(ComicPageAnchor(pageIndex: target,
                    fraction: next.targetFraction).fraction))
                let expected = generation
                DispatchQueue.main.async { [weak self, weak strip] in
                    guard let self, let strip, self.generation == expected, self.view.targetPage == target,
                          let anchor = self.pendingTargetAnchor else { return }
                    self.isRestoringAnchor = true
                    strip.layoutIfNeeded()
                    strip.scrollToItem(at: IndexPath(item: target, section: 0), at: .top, animated: false)
                    strip.layoutIfNeeded()
                    self.restoreAnchor(anchor)
                    self.isRestoringAnchor = false
                    if self.sizes[target] != nil { self.pendingTargetAnchor = nil }
                    self.view.onTargetApplied()
                    self.publishVisiblePage()
                }
            }
        }

        func cancelLoads() {
            for load in loads.values { load.task.cancel() }
            loads.removeAll()
        }

        func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
            view.requests.count + 1
        }

        func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
            let index = indexPath.item
            if index == view.requests.count {
                let footer = collectionView.dequeueReusableCell(withReuseIdentifier: "footer", for: indexPath) as! ComicStripFooterCell
                footer.configure(title: view.footerTitle, isEnabled: view.canActivateFooter, action: view.onFooter)
                return footer
            }
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "page", for: indexPath) as! ComicStripImageCell
            configure(cell, at: index)
            return cell
        }

        private func configure(_ cell: ComicStripImageCell, at index: Int, image suppliedImage: UIImage? = nil) {
            guard view.requests.indices.contains(index), let url = URL(string: view.requests[index].url) else { return }
            let request = view.requests[index]
            let image = suppliedImage ?? RemoteImageLoader.shared.cachedComicPage(for: url, headers: request.headers,
                                                                 maxPixelSize: ComicPagePositionPolicy.maxImagePixels)
            cell.configure(image: image, page: index + 1, failure: failures[index], reducesMotion: view.reducesMotion)
            cell.onTap = view.onTap
            cell.onRefreshAddresses = view.onRefreshAddresses
            cell.onRetry = { [weak self] in
                guard let self else { return }
                self.failures.removeValue(forKey: index)
                if let visible = self.strip?.cellForItem(at: IndexPath(item: index, section: 0)) as? ComicStripImageCell {
                    self.configure(visible, at: index)
                }
                self.beginLoad(index)
            }
            cell.onZoomChanged = { [weak self] zooming in
                guard let self else { return }
                if zooming { self.zoomedPage = index }
                else if self.zoomedPage == index { self.zoomedPage = nil }
                else { return }
                self.strip?.isScrollEnabled = !zooming
                if !zooming { self.settlePosition() }
            }
        }

        func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
            if view.requests.indices.contains(indexPath.item) { beginLoad(indexPath.item) }
        }

        func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout,
                            sizeForItemAt indexPath: IndexPath) -> CGSize {
            let width = max(view.viewportWidth, 1)
            let height = indexPath.item == view.requests.count ? 88 :
                ComicStripGeometry.height(for: sizes[indexPath.item], width: width)
            return CGSize(width: width, height: height)
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            guard !isRestoringAnchor, !isZooming else { return }
            publishVisiblePage()
        }

        func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
            // Once the reader moves, a late image must never pull them back to resume.
            pendingTargetAnchor = nil
            view.onTargetApplied()
        }

        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
            if !decelerate { settlePosition() }
        }

        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) { settlePosition() }
        func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) { settlePosition() }

        private func settlePosition() {
            applyPendingSizes()
            reportPosition(captureAnchor(), isSettled: true)
        }

        private func reportPosition(_ visible: Anchor?, isSettled: Bool = false) {
            if let visible, view.requests.indices.contains(visible.index), sizes[visible.index] != nil {
                let value = "第 \(visible.index + 1) 页 · \(Int(visible.fraction * 100))%"
                if strip?.accessibilityValue != value { strip?.accessibilityValue = value }
            }
            guard let anchor = pendingTargetAnchor ?? visible, view.requests.indices.contains(anchor.index) else { return }
            view.onPosition(ComicPageAnchor(pageIndex: anchor.index, fraction: Double(anchor.fraction)), isSettled)
        }

        private func publishVisiblePage() {
            let visible = captureAnchor()
            reportPosition(visible)
            guard pendingTargetAnchor == nil else { return }
            guard let anchor = visible, view.requests.indices.contains(anchor.index),
                  reportedPage != anchor.index else { return }
            let direction = anchor.index < reportedPage ? -1 : 1
            reportedPage = anchor.index
            view.onVisiblePage(anchor.index)
            let order = [anchor.index] + ComicPagePositionPolicy.neighbours(of: anchor.index, count: view.requests.count, direction: direction)
            let keep = Set(order)
            for index in Array(loads.keys) where !keep.contains(index) &&
                strip?.indexPathsForVisibleItems.contains(IndexPath(item: index, section: 0)) != true {
                loads.removeValue(forKey: index)?.task.cancel()
            }
            if !ProcessInfo.processInfo.isLowPowerModeEnabled, ProcessInfo.processInfo.thermalState.rawValue < 2 {
                for index in order { beginLoad(index) }
            }
        }

        private func beginLoad(_ index: Int) {
            guard loads[index] == nil, failures[index] == nil, view.requests.indices.contains(index),
                  let url = URL(string: view.requests[index].url) else { return }
            let request = view.requests[index]
            let expected = generation
            let id = UUID()
            let task = Task { @MainActor [weak self] in
                let result = await RemoteImageLoader.shared.comicPage(for: url, headers: request.headers,
                    maxPixelSize: ComicPagePositionPolicy.maxImagePixels)
                guard !Task.isCancelled, let self, self.generation == expected, self.loads[index]?.id == id else { return }
                self.loads.removeValue(forKey: index)
                let displayed: UIImage?
                switch result {
                case .success(let image):
                    displayed = image
                    self.failures.removeValue(forKey: index)
                    self.acceptSize(image.size, for: index)
                case .failure(let failure):
                    displayed = nil
                    if failure != .cancelled { self.failures[index] = failure }
                }
                if let cell = self.strip?.cellForItem(at: IndexPath(item: index, section: 0)) as? ComicStripImageCell {
                    self.configure(cell, at: index, image: displayed)
                }
            }
            loads[index] = Load(id: id, task: task)
        }

        /// Defers geometry above/inside the viewport until system inertia finishes.
        func acceptSize(_ size: CGSize, for index: Int) {
            guard let strip, size.width > 0, size.height > 0,
                  sizes[index] != size, pendingSizes[index] != size else { return }
            let lastVisible = strip.indexPathsForVisibleItems.map(\.item).max() ?? 0
            if isZooming || ((strip.isDragging || strip.isDecelerating || strip.isTracking) && index <= lastVisible) {
                pendingSizes[index] = size
                deferredSizeCount += 1
                return
            }
            let anchor = pendingTargetAnchor ?? captureAnchor()
            sizes[index] = size
            refreshGeometry(around: anchor)
            if pendingTargetAnchor?.index == index, view.targetPage == nil { pendingTargetAnchor = nil }
            publishVisiblePage()
        }

        private func applyPendingSizes() {
            guard let strip, !isZooming, !strip.isDragging, !strip.isDecelerating, !pendingSizes.isEmpty else { return }
            let anchor = pendingTargetAnchor ?? captureAnchor()
            sizes.merge(pendingSizes, uniquingKeysWith: { _, latest in latest })
            pendingSizes.removeAll()
            refreshGeometry(around: anchor)
            if let target = pendingTargetAnchor, sizes[target.index] != nil, view.targetPage == nil { pendingTargetAnchor = nil }
            publishVisiblePage()
        }

        private func refreshGeometry(around anchor: Anchor?) {
            guard let strip else { return }
            isRestoringAnchor = true
            strip.collectionViewLayout.invalidateLayout()
            strip.layoutIfNeeded()
            restoreAnchor(anchor)
            isRestoringAnchor = false
        }

        private func captureAnchor() -> Anchor? {
            guard let strip else { return nil }
            let line = max(strip.contentOffset.y, 0)
            // Visible cells can lag contentOffset until the next layout pass.
            // Query layout at the current reading line, not the old visible set.
            let probe = CGRect(x: 0, y: line + 0.5, width: strip.bounds.width, height: 1)
            let attributes = strip.collectionViewLayout.layoutAttributesForElements(in: probe) ?? []
            guard let first = attributes.filter({ $0.representedElementCategory == .cell &&
                $0.frame.minY <= line + 0.5 && $0.frame.maxY > line + 0.5 })
                .min(by: { $0.indexPath.item < $1.indexPath.item }) else { return nil }
            return Anchor(index: first.indexPath.item,
                          fraction: max(0, min((strip.contentOffset.y - first.frame.minY) / max(first.frame.height, 1), 1)))
        }

        private func restoreAnchor(_ anchor: Anchor?) {
            guard let strip, let anchor, let attributes = strip.layoutAttributesForItem(at: IndexPath(item: anchor.index, section: 0)) else { return }
            let requested = attributes.frame.minY + attributes.frame.height * anchor.fraction
            let offset = max(0, min(requested, max(strip.contentSize.height - strip.bounds.height, 0)))
            guard abs(offset - strip.contentOffset.y) > 0.5 else { return }
            strip.setContentOffset(CGPoint(x: 0, y: offset), animated: false)
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
