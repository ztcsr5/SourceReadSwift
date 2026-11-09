import SwiftUI
import UIKit

/// 隐藏系统导航栏后，交互式返回手势会被系统一起关掉。
/// 把 delegate 释放并重新启用即可恢复「左缘右滑返回」，且不恢复那条空白导航栏。
struct InteractivePopGestureEnabler: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> PopController { PopController() }

    func updateUIViewController(_ controller: PopController, context: Context) {
        controller.enable()
    }

    final class PopController: UIViewController {
        override func loadView() {
            view = UIView()
            view.backgroundColor = .clear
            view.isUserInteractionEnabled = false
        }

        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            enable()
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            enable()
        }

        func enable() {
            guard let navigation = navigationController else { return }
            navigation.interactivePopGestureRecognizer?.delegate = nil
            navigation.interactivePopGestureRecognizer?.isEnabled = true
        }
    }
}
