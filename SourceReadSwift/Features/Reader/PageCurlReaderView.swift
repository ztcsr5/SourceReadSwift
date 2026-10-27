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
    let pageBuilder: (Item) -> Content

    init(
        pages: [Item],
        contentRevision: String,
        transitionStyle: UIPageViewController.TransitionStyle = .pageCurl,
        currentPageIndex: Binding<Int>,
        onPageChanged: ((Int) -> Void)? = nil,
        onPageContainerLayout: ((CGSize, CGFloat) -> Void)? = nil,
        @ViewBuilder pageBuilder: @escaping (Item) -> Content
    ) {
        self.pages = pages
        self.contentRevision = contentRevision
        self.transitionStyle = transitionStyle
        self._currentPageIndex = currentPageIndex
        self.onPageChanged = onPageChanged
        self.onPageContainerLayout = onPageContainerLayout
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
        private var isUserInteracting = false

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

        func viewController(at index: Int) -> UIViewController {
            guard parent.pages.indices.contains(index) else {
                return UIViewController()
            }
            let item = parent.pages[index]
            let view = parent.pageBuilder(item)
            let controller = PageHostingController(
                rootView: view,
                pageIndex: index,
                onLayout: parent.onPageContainerLayout
            )
            controller.view.backgroundColor = .clear
            return controller
        }

        func sync(_ pageViewController: UIPageViewController, contentRevision: String) {
            guard !parent.pages.isEmpty else { return }
            let displayedIndex = (pageViewController.viewControllers?.first as? PageHostingController<Content>)?.pageIndex
            let desiredIndex = ReaderPagedNavigationPolicy.clampedPageIndex(
                parent.currentPageIndex,
                pageCount: parent.pages.count
            )
            let decision = ReaderPageCurlSyncPolicy.decision(
                displayedIndex: displayedIndex,
                desiredIndex: desiredIndex,
                pageCount: parent.pages.count,
                contentRevisionChanged: contentRevision != lastContentRevision,
                isUserInteracting: isUserInteracting
            )

            switch decision {
            case .none:
                break
            case .reloadCurrentPage:
                let controller = viewController(at: desiredIndex)
                pageViewController.setViewControllers(
                    [controller],
                    direction: .forward,
                    animated: false,
                    completion: nil
                )
                lastContentRevision = contentRevision
            case .move(let target):
                let controller = viewController(at: target)
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
                lastContentRevision = contentRevision
            }
        }

        func pageViewController(
            _ pageViewController: UIPageViewController,
            viewControllerBefore viewController: UIViewController
        ) -> UIViewController? {
            guard let host = viewController as? PageHostingController<Content> else { return nil }
            let previous = host.pageIndex - 1
            guard previous >= 0 else { return nil }
            return self.viewController(at: previous)
        }

        func pageViewController(
            _ pageViewController: UIPageViewController,
            viewControllerAfter viewController: UIViewController
        ) -> UIViewController? {
            guard let host = viewController as? PageHostingController<Content> else { return nil }
            let next = host.pageIndex + 1
            guard next < parent.pages.count else { return nil }
            return self.viewController(at: next)
        }

        func pageViewController(
            _ pageViewController: UIPageViewController,
            willTransitionTo pendingViewControllers: [UIViewController]
        ) {
            isUserInteracting = true
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
                let newIndex = currentVC.pageIndex
                parent.currentPageIndex = newIndex
                parent.onPageChanged?(newIndex)
            }
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
    private let onLayout: ((CGSize, CGFloat) -> Void)?
    private var lastReportedSize: CGSize = .zero
    private var lastReportedMinY: CGFloat = .greatestFiniteMagnitude

    init(rootView: Content, pageIndex: Int, onLayout: ((CGSize, CGFloat) -> Void)?) {
        self.pageIndex = pageIndex
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
