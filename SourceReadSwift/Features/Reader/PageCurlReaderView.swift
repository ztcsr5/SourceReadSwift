import Foundation
import SwiftUI
import UIKit

/// iOS 原生 3D 仿真翻页容器（Page Curl）。
/// 使用 UIPageViewController 实现 120Hz 硬件加速的纸张卷曲与阴影。
///
/// SwiftUI 只提供页模型；手势由 UIKit 自己拥有，避免 SwiftUI 在用户拖动
/// 过程中再次 setViewControllers 造成动画竞争。
struct PageCurlReaderView<Item: Identifiable, Content: View>: UIViewControllerRepresentable {
    let pages: [Item]
    /// Changes whenever the page model is rebuilt (typography, viewport or
    /// chapter content).  The coordinator rebuilds the visible hosting
    /// controller so a font change can never leave stale page content on
    /// screen — index equality alone is not enough.
    let contentRevision: String
    let transitionStyle: UIPageViewController.TransitionStyle
    @Binding var currentPageIndex: Int
    let onPageChanged: ((Int) -> Void)?
    /// 页面容器的真实尺寸与窗口坐标原点。分页引擎用它校准正文高度；
    /// 默认 nil 时为旧行为（只靠根视口）。
    let onPageContainerLayout: ((CGSize, CGFloat) -> Void)?
    /// Reports the stable identity of the page the user can actually see.
    /// `ReaderView` uses it as the anchor when the page model is rebuilt, so
    /// an array-index shift can never move the reader into another chapter.
    let onVisiblePageIdentity: ((String) -> Void)?
    /// Page-turn gestures are owned by UIPageViewController. The reader uses
    /// this signal to postpone any page-model rebuild until the gesture ends.
    let onInteractionChanged: ((Bool) -> Void)?
    /// Stable key for one item; defaults to its `Identifiable` id.
    let pageKey: (Item) -> String
    /// Per-page content signature (typography, theme, text). A chapter that is
    /// prefetched above the reader changes the window revision but not the
    /// pages already on screen, so the hosting cache is keyed by this value
    /// instead of the window-wide revision. `nil` falls back to
    /// `contentRevision`.
    let pageRevision: ((Item) -> String)?
    let pageBuilder: (Item) -> Content

    init(
        pages: [Item],
        contentRevision: String,
        transitionStyle: UIPageViewController.TransitionStyle = .pageCurl,
        currentPageIndex: Binding<Int>,
        onPageChanged: ((Int) -> Void)? = nil,
        onPageContainerLayout: ((CGSize, CGFloat) -> Void)? = nil,
        onVisiblePageIdentity: ((String) -> Void)? = nil,
        onInteractionChanged: ((Bool) -> Void)? = nil,
        pageKey: @escaping (Item) -> String = { item in String(describing: item.id) },
        pageRevision: ((Item) -> String)? = nil,
        @ViewBuilder pageBuilder: @escaping (Item) -> Content
    ) {
        self.pages = pages
        self.contentRevision = contentRevision
        self.transitionStyle = transitionStyle
        self._currentPageIndex = currentPageIndex
        self.onPageChanged = onPageChanged
        self.onPageContainerLayout = onPageContainerLayout
        self.onVisiblePageIdentity = onVisiblePageIdentity
        self.onInteractionChanged = onInteractionChanged
        self.pageKey = pageKey
        self.pageRevision = pageRevision
        self.pageBuilder = pageBuilder
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIViewController(context: Context) -> UIPageViewController {
        let options: [UIPageViewController.OptionsKey: Any]
        if transitionStyle == .pageCurl {
            options = [
                UIPageViewController.OptionsKey.spineLocation: UIPageViewController.SpineLocation.min.rawValue
            ]
        } else {
            options = [
                UIPageViewController.OptionsKey.interPageSpacing: 0
            ]
        }
        let pvc = UIPageViewController(
            transitionStyle: transitionStyle,
            navigationOrientation: .horizontal,
            options: options
        )
        pvc.dataSource = context.coordinator
        pvc.delegate = context.coordinator
        pvc.isDoubleSided = false
        pvc.view.backgroundColor = .clear
        pvc.view.clipsToBounds = true
        // UIPageViewController 默认会把子控制器再内缩一层安全区：分页按全屏算、
        // 页面只拿到 793pt，最后一行就被裁掉。这里把整条 UIKit 链路的
        // safe-area / layout-margin 全部关掉，SwiftUI 页自己负责页眉页脚位置。
        pvc.edgesForExtendedLayout = .all
        pvc.extendedLayoutIncludesOpaqueBars = true
        pvc.viewRespectsSystemMinimumLayoutMargins = false
        pvc.view.insetsLayoutMarginsFromSafeArea = false
        pvc.view.layoutMargins = .zero
        pvc.additionalSafeAreaInsets = .zero

        let initialIndex = ReaderPagedNavigationPolicy.clampedPageIndex(
            currentPageIndex,
            pageCount: pages.count
        )
        let initialVC = context.coordinator.viewController(at: initialIndex)
        pvc.setViewControllers([initialVC], direction: .forward, animated: false, completion: nil)
        context.coordinator.lastContentRevision = contentRevision
        context.coordinator.lastDesiredIndex = initialIndex
        context.coordinator.noteContentRevision(contentRevision)
        context.coordinator.reportVisibleIdentity(initialVC)
        context.coordinator.prewarm(around: initialIndex)
        context.coordinator.suppressInternalTapGestures(on: pvc)
        context.coordinator.normalizeInternalScrollViews(in: pvc.view)
        DispatchQueue.main.async {
            context.coordinator.suppressInternalTapGestures(on: pvc)
            context.coordinator.normalizeInternalScrollViews(in: pvc.view)
        }
        return pvc
    }

    func updateUIViewController(_ uiViewController: UIPageViewController, context: Context) {
        context.coordinator.parent = self
        context.coordinator.suppressInternalTapGestures(on: uiViewController)
        context.coordinator.normalizeInternalScrollViews(in: uiViewController.view)
        context.coordinator.sync(uiViewController, contentRevision: contentRevision)
    }

    final class Coordinator: NSObject, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
        var parent: PageCurlReaderView
        var lastContentRevision = ""
        /// Last page index SwiftUI asked for. A mismatch with the live
        /// binding means an explicit jump (TOC, TTS); a match means the page
        /// array shifted underneath the reader and the visible index wins.
        var lastDesiredIndex: Int?
        private var isUserInteracting = false
        private var cachedRevision = ""
        private var hostingControllers: [String: PageHostingController<Content>] = [:]
        private var hostingOrder: [String] = []

        init(_ parent: PageCurlReaderView) {
            self.parent = parent
        }

        /// 仿真翻页的 UIPageViewController 自带一个「点一下翻一页」的 tap 手势；
        /// SwiftUI 的九宫格点按区又会翻一次，用户轻点一次会连翻两页。
        /// 只关 tap，保留拖动卷页的 pan。
        func suppressInternalTapGestures(on pageViewController: UIPageViewController) {
            guard parent.transitionStyle == .pageCurl else { return }
            for gesture in pageViewController.gestureRecognizers {
                let name = String(describing: type(of: gesture))
                if gesture is UITapGestureRecognizer || name.localizedCaseInsensitiveContains("tap") {
                    gesture.isEnabled = false
                }
            }
        }

        /// 滑动翻页内部是一个 UIScrollView；它的 `contentInsetAdjustmentBehavior`
        /// 默认会自动加安全区，导致页面内容整体下移、底部被裁。这里统一改成 never。
        func normalizeInternalScrollViews(in view: UIView) {
            if let scrollView = view as? UIScrollView {
                scrollView.contentInsetAdjustmentBehavior = .never
                scrollView.contentInset = .zero
                scrollView.scrollIndicatorInsets = .zero
            }
            for subview in view.subviews {
                normalizeInternalScrollViews(in: subview)
            }
        }

        /// Reuse the hosting controllers that surround the visible page. The
        /// old code built a fresh SwiftUI tree (including a full attributed
        /// page) inside `viewControllerBefore/After` while the finger was
        /// already moving, which showed up as a hitch at the start of every
        /// swipe. Eight entries cover the visible page plus two neighbours on
        /// both sides in the three paged modes.
        func viewController(at index: Int) -> UIViewController {
            guard parent.pages.indices.contains(index) else {
                return UIViewController()
            }
            let item = parent.pages[index]
            let key = parent.pageKey(item)
            let revision = parent.pageRevision?(item) ?? parent.contentRevision
            if let cached = hostingControllers[key], cached.contentRevision == revision {
                return cached
            }

            let controller = PageHostingController(
                rootView: parent.pageBuilder(item),
                pageIndex: index,
                pageKey: key,
                contentRevision: revision,
                onLayout: parent.onPageContainerLayout
            )
            controller.view.backgroundColor = .clear
            // A rebuilt page (typography or theme change) replaces the cached
            // entry in place; the key stays the same so the LRU order holds.
            if hostingControllers.updateValue(controller, forKey: key) == nil {
                hostingOrder.append(key)
            }
            while hostingOrder.count > 8 {
                let evicted = hostingOrder.removeFirst()
                hostingControllers.removeValue(forKey: evicted)
            }
            return controller
        }

        /// Track the window-wide revision without discarding cached pages.
        /// Per-page content invalidation is handled by `pageRevision` above;
        /// clearing here used to rebuild every visible page whenever a
        /// neighbouring chapter finished prefetching.
        func noteContentRevision(_ revision: String) {
            cachedRevision = revision
        }

        /// Build the next/previous pages after the current frame has been
        /// committed. Prebuilding them inside the gesture is what caused the
        /// visible half-second stall on the first swipe after a chapter load.
        func prewarm(around index: Int) {
            let candidates = [index + 1, index - 1, index + 2]
            DispatchQueue.main.async { [weak self] in
                guard let self, self.cachedRevision == self.parent.contentRevision else { return }
                for candidate in candidates where self.parent.pages.indices.contains(candidate) {
                    _ = self.viewController(at: candidate)
                }
            }
        }

        func reportVisibleIdentity(_ controller: UIViewController?) {
            guard let host = controller as? PageHostingController<Content> else { return }
            parent.onVisiblePageIdentity?(host.pageKey)
        }

        func sync(_ pageViewController: UIPageViewController, contentRevision: String) {
            guard !parent.pages.isEmpty else { return }
            noteContentRevision(contentRevision)
            let displayedController = pageViewController.viewControllers?.first
            let displayedHost = displayedController as? PageHostingController<Content>
            // `host.pageIndex` belongs to the revision the controller was
            // built with. Resolve through the stable page key so a chapter
            // inserted above the reader cannot make the cursor drift into an
            // earlier chapter.
            let displayedIndex = displayedHost.flatMap { currentIndex(for: $0) }
            let desiredIndex = ReaderPagedNavigationPolicy.clampedPageIndex(
                parent.currentPageIndex,
                pageCount: parent.pages.count
            )
            let visiblePageChanged: Bool = {
                guard let host = displayedHost,
                      let index = displayedIndex,
                      parent.pages.indices.contains(index) else {
                    return contentRevision != lastContentRevision
                }
                let revision = parent.pageRevision?(parent.pages[index]) ?? contentRevision
                return revision != host.contentRevision
            }()
            let decision = ReaderPageCurlSyncPolicy.decision(
                displayedIndex: displayedIndex,
                desiredIndex: desiredIndex,
                pageCount: parent.pages.count,
                contentRevisionChanged: visiblePageChanged,
                isUserInteracting: isUserInteracting,
                lastDesiredIndex: lastDesiredIndex
            )
            lastDesiredIndex = desiredIndex

            switch decision {
            case .none:
                reportVisibleIdentity(displayedController)
            case .adopt(let visible):
                // A prefetched chapter was inserted above the reader: the
                // page on screen is unchanged, only its array index moved.
                // Sending `setViewControllers` to the stale index here is
                // what produced the “chapter 5 jumps back to chapter 2”
                // report.
                adoptVisibleIndex(visible, staleDesired: desiredIndex, controller: displayedController)
            case .reloadCurrentPage:
                let target = displayedIndex ?? desiredIndex
                let controller = viewController(at: target)
                lastContentRevision = contentRevision
                guard controller !== displayedController else {
                    // Same page object; nothing to reload.
                    reportVisibleIdentity(controller)
                    return
                }
                pageViewController.setViewControllers(
                    [controller],
                    direction: .forward,
                    animated: false,
                    completion: nil
                )
                reportVisibleIdentity(controller)
                prewarm(around: target)
            case .move(let target):
                let controller = viewController(at: target)
                lastContentRevision = contentRevision
                guard controller !== displayedController else {
                    // The index moved because the window gained or lost a
                    // chapter, but the page itself is unchanged. Animating a
                    // `setViewControllers` here produced the stutter and the
                    // half-rendered double page at every chapter boundary.
                    reportVisibleIdentity(controller)
                    prewarm(around: target)
                    return
                }
                let direction: UIPageViewController.NavigationDirection = {
                    guard let displayedIndex else { return .forward }
                    return target >= displayedIndex ? .forward : .reverse
                }()
                pageViewController.setViewControllers(
                    [controller],
                    direction: direction,
                    animated: displayedIndex != nil,
                    completion: nil
                )
                reportVisibleIdentity(controller)
                prewarm(around: target)
            }
        }

        /// Writes the page that is actually on screen back into
        /// `pagedPageIndex` after the page array shifted above it. Deferred and
        /// guarded so an explicit jump issued in the same frame still wins.
        private func adoptVisibleIndex(_ visible: Int, staleDesired: Int, controller: UIViewController?) {
            reportVisibleIdentity(controller)
            prewarm(around: visible)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                guard self.parent.pages.indices.contains(visible) else { return }
                guard self.parent.currentPageIndex == staleDesired,
                      self.parent.currentPageIndex != visible else { return }
                self.parent.currentPageIndex = visible
            }
        }

        /// Resolve the index of a hosting controller against the current page
        /// array. The stored index belongs to the revision the controller was
        /// built with; after a window insert it is stale even though the page
        /// content itself is unchanged. The stable page key survives that
        /// rebuild, so it is the only safe index source here.
        private func currentIndex(for host: PageHostingController<Content>) -> Int? {
            if parent.pages.indices.contains(host.pageIndex),
               parent.pageKey(parent.pages[host.pageIndex]) == host.pageKey {
                return host.pageIndex
            }
            return parent.pages.firstIndex { parent.pageKey($0) == host.pageKey }
        }

        func pageViewController(
            _ pageViewController: UIPageViewController,
            viewControllerBefore viewController: UIViewController
        ) -> UIViewController? {
            guard let host = viewController as? PageHostingController<Content>,
                  let current = currentIndex(for: host) else { return nil }
            let previous = current - 1
            guard previous >= 0 else { return nil }
            return self.viewController(at: previous)
        }

        func pageViewController(
            _ pageViewController: UIPageViewController,
            viewControllerAfter viewController: UIViewController
        ) -> UIViewController? {
            guard let host = viewController as? PageHostingController<Content>,
                  let current = currentIndex(for: host) else { return nil }
            let next = current + 1
            guard next < parent.pages.count else { return nil }
            return self.viewController(at: next)
        }

        func pageViewController(
            _ pageViewController: UIPageViewController,
            willTransitionTo pendingViewControllers: [UIViewController]
        ) {
            isUserInteracting = true
            parent.onInteractionChanged?(true)
        }

        func pageViewController(
            _ pageViewController: UIPageViewController,
            didFinishAnimating finished: Bool,
            previousViewControllers: [UIViewController],
            transitionCompleted completed: Bool
        ) {
            isUserInteracting = false
            if completed,
               let currentVC = pageViewController.viewControllers?.first as? PageHostingController<Content> {
                // The visible page may have been built before a chapter was
                // inserted above it. Translate its stable key into the new
                // array instead of trusting the old index, which used to land
                // on chapter 2 after reading chapter 5.
                let newIndex = currentIndex(for: currentVC)
                    ?? ReaderPagedNavigationPolicy.clampedPageIndex(
                        parent.currentPageIndex,
                        pageCount: parent.pages.count
                    )
                parent.currentPageIndex = newIndex
                lastDesiredIndex = newIndex
                parent.onPageChanged?(newIndex)
                reportVisibleIdentity(currentVC)
            }
            parent.onInteractionChanged?(false)
            // Apply a page-model revision that arrived while the finger owned
            // the transition.  SwiftUI may not call updateUIViewController a
            // second time after the gesture ends.
            DispatchQueue.main.async { [weak self, weak pageViewController] in
                guard let self, let pageViewController else { return }
                self.normalizeInternalScrollViews(in: pageViewController.view)
                self.sync(pageViewController, contentRevision: self.parent.contentRevision)
            }
        }
    }
}

private final class PageHostingController<Content: View>: UIHostingController<Content> {
    let pageIndex: Int
    let pageKey: String
    let contentRevision: String
    private let onLayout: ((CGSize, CGFloat) -> Void)?
    private var lastReportedSize: CGSize = .zero
    private var lastReportedMinY: CGFloat = .greatestFiniteMagnitude

    init(
        rootView: Content,
        pageIndex: Int,
        pageKey: String,
        contentRevision: String,
        onLayout: ((CGSize, CGFloat) -> Void)?
    ) {
        self.pageIndex = pageIndex
        self.pageKey = pageKey
        self.contentRevision = contentRevision
        self.onLayout = onLayout
        super.init(rootView: rootView)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        view.clipsToBounds = true
        edgesForExtendedLayout = .all
        extendedLayoutIncludesOpaqueBars = true
        viewRespectsSystemMinimumLayoutMargins = false
        view.insetsLayoutMarginsFromSafeArea = false
        view.layoutMargins = .zero
        additionalSafeAreaInsets = .zero
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        view.clipsToBounds = true

        let size = view.bounds.size
        guard size.width > 1, size.height > 1, let onLayout else { return }
        let minY = view.convert(view.bounds, to: nil).minY
        guard abs(size.width - lastReportedSize.width) > 0.5
                || abs(size.height - lastReportedSize.height) > 0.5
                || abs(minY - lastReportedMinY) > 0.5 else { return }
        lastReportedSize = size
        lastReportedMinY = minY
        // layoutSubviews 期间直接改 SwiftUI @State 会触发 "modifying state
        // during view update"；推迟到下一轮主线程。
        DispatchQueue.main.async {
            onLayout(size, minY)
        }
    }

    @MainActor required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
