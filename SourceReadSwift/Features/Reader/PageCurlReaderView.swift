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
    let pageBuilder: (Item) -> Content

    init(
        pages: [Item],
        contentRevision: String,
        transitionStyle: UIPageViewController.TransitionStyle = .pageCurl,
        currentPageIndex: Binding<Int>,
        onPageChanged: ((Int) -> Void)? = nil,
        @ViewBuilder pageBuilder: @escaping (Item) -> Content
    ) {
        self.pages = pages
        self.contentRevision = contentRevision
        self.transitionStyle = transitionStyle
        self._currentPageIndex = currentPageIndex
        self.onPageChanged = onPageChanged
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

        let initialIndex = ReaderPagedNavigationPolicy.clampedPageIndex(
            currentPageIndex,
            pageCount: pages.count
        )
        let initialVC = context.coordinator.viewController(at: initialIndex)
        pvc.setViewControllers([initialVC], direction: .forward, animated: false, completion: nil)
        context.coordinator.lastContentRevision = contentRevision
        return pvc
    }

    func updateUIViewController(_ uiViewController: UIPageViewController, context: Context) {
        context.coordinator.parent = self
        context.coordinator.sync(uiViewController, contentRevision: contentRevision)
    }

    final class Coordinator: NSObject, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
        var parent: PageCurlReaderView
        var lastContentRevision = ""
        private var isUserInteracting = false

        init(_ parent: PageCurlReaderView) {
            self.parent = parent
        }

        func viewController(at index: Int) -> UIViewController {
            guard parent.pages.indices.contains(index) else {
                return UIViewController()
            }
            let item = parent.pages[index]
            let view = parent.pageBuilder(item)
            let controller = PageHostingController(rootView: view, pageIndex: index)
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
                self.sync(pageViewController, contentRevision: self.parent.contentRevision)
            }
        }
    }
}

private final class PageHostingController<Content: View>: UIHostingController<Content> {
    let pageIndex: Int

    init(rootView: Content, pageIndex: Int) {
        self.pageIndex = pageIndex
        super.init(rootView: rootView)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        view.clipsToBounds = true
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        view.clipsToBounds = true
    }

    @MainActor required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
