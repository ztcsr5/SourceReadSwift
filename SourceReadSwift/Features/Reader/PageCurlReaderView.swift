import Foundation
import SwiftUI
import UIKit

/// iOS 原生 3D 仿真翻页控制器（Page Curl）
/// 基于 UIPageViewController 实现 120Hz 硬件加速纸张卷曲、物理背面阴影与手势交互
struct PageCurlReaderView<Item: Identifiable, Content: View>: UIViewControllerRepresentable {
    let pages: [Item]
    @Binding var currentPageIndex: Int
    let onPageChanged: ((Int) -> Void)?
    let pageBuilder: (Item) -> Content

    init(
        pages: [Item],
        currentPageIndex: Binding<Int>,
        onPageChanged: ((Int) -> Void)? = nil,
        @ViewBuilder pageBuilder: @escaping (Item) -> Content
    ) {
        self.pages = pages
        self._currentPageIndex = currentPageIndex
        self.onPageChanged = onPageChanged
        self.pageBuilder = pageBuilder
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIViewController(context: Context) -> UIPageViewController {
        let pvc = UIPageViewController(
            transitionStyle: .pageCurl,
            navigationOrientation: .horizontal,
            options: [
                UIPageViewController.OptionsKey.spineLocation: UIPageViewController.SpineLocation.min.rawValue
            ]
        )
        pvc.dataSource = context.coordinator
        pvc.delegate = context.coordinator
        pvc.isDoubleSided = false

        let initialVC = context.coordinator.viewController(at: currentPageIndex)
        pvc.setViewControllers([initialVC], direction: .forward, animated: false, completion: nil)
        return pvc
    }

    func updateUIViewController(_ uiViewController: UIPageViewController, context: Context) {
        context.coordinator.parent = self
        guard let currentVC = uiViewController.viewControllers?.first as? PageHostingController<Content> else { return }
        if currentVC.pageIndex != currentPageIndex, pages.indices.contains(currentPageIndex) {
            let targetVC = context.coordinator.viewController(at: currentPageIndex)
            let direction: UIPageViewController.NavigationDirection = currentPageIndex > currentVC.pageIndex ? .forward : .reverse
            uiViewController.setViewControllers([targetVC], direction: direction, animated: true, completion: nil)
        }
    }

    final class Coordinator: NSObject, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
        var parent: PageCurlReaderView

        init(_ parent: PageCurlReaderView) {
            self.parent = parent
        }

        func viewController(at index: Int) -> UIViewController {
            guard parent.pages.indices.contains(index) else {
                return UIViewController()
            }
            let item = parent.pages[index]
            let view = parent.pageBuilder(item)
            let hc = PageHostingController(rootView: view, pageIndex: index)
            hc.view.backgroundColor = .clear
            return hc
        }

        func pageViewController(
            _ pageViewController: UIPageViewController,
            viewControllerBefore viewController: UIViewController
        ) -> UIViewController? {
            guard let hc = viewController as? PageHostingController<Content> else { return nil }
            let prev = hc.pageIndex - 1
            guard prev >= 0 else { return nil }
            return self.viewController(at: prev)
        }

        func pageViewController(
            _ pageViewController: UIPageViewController,
            viewControllerAfter viewController: UIViewController
        ) -> UIViewController? {
            guard let hc = viewController as? PageHostingController<Content> else { return nil }
            let next = hc.pageIndex + 1
            guard next < parent.pages.count else { return nil }
            return self.viewController(at: next)
        }

        func pageViewController(
            _ pageViewController: UIPageViewController,
            didFinishAnimating finished: Bool,
            previousViewControllers: [UIViewController],
            transitionCompleted completed: Bool
        ) {
            if completed,
               let currentVC = pageViewController.viewControllers?.first as? PageHostingController<Content> {
                let newIndex = currentVC.pageIndex
                parent.currentPageIndex = newIndex
                parent.onPageChanged?(newIndex)
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

    @MainActor required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
