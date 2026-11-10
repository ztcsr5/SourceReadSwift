import SwiftUI
import UIKit

/// An interactive pop may begin before UIKit removes the source from the stack.
enum ReaderNativePopPolicy {
    static func isPop(from source: UIViewController, to target: UIViewController?,
                      in navigation: UINavigationController, isInteractive: Bool) -> Bool {
        let stack = navigation.viewControllers
        if source.isMovingFromParent || !stack.contains(where: { $0 === source }) {
            return true
        }
        // A fast flick can finish before `isMovingFromParent` flips. Compare
        // stack order instead so the tab chrome is released for animated and
        // state-driven pops alike, while a push (target above source) is not.
        guard let target,
              let sourceIndex = stack.firstIndex(where: { $0 === source }),
              let targetIndex = stack.firstIndex(where: { $0 === target }) else { return false }
        _ = isInteractive
        return targetIndex < sourceIndex
    }
}

/// Releases only this reader's tab-bar ownership when a real pop starts, restoring it on cancellation.
struct ReaderTabChromeExitBridge: UIViewControllerRepresentable {
    let owner: UUID
    @EnvironmentObject private var appState: AppState

    func makeUIViewController(context: Context) -> ReaderTabChromeExitController {
        let controller = ReaderTabChromeExitController()
        configure(controller)
        return controller
    }

    func updateUIViewController(_ controller: ReaderTabChromeExitController, context: Context) {
        configure(controller)
    }

    private func configure(_ controller: ReaderTabChromeExitController) {
        controller.configure(onLeaving: { appState.releaseTabChromeHidden(owner: owner) },
            onCancelled: { appState.acquireTabChromeHidden(owner: owner) })
    }
}

final class ReaderTabChromeExitController: UIViewController {
    private var hasPreparedExit = false
    private var onLeaving: () -> Void = {}
    private var onCancelled: () -> Void = {}

    override func loadView() {
        view = UIView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
    }

    func configure(onLeaving: @escaping () -> Void, onCancelled: @escaping () -> Void) {
        self.onLeaving = onLeaving
        self.onCancelled = onCancelled
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        guard let transition = transitionCoordinator,
              let source = transition.viewController(forKey: .from), belongs(to: source),
              let navigation = source.navigationController ?? navigationController else {
            NavigationTrace.shared.mark("pop", "willDisappear 没有转场上下文")
            return
        }
        let isPop = ReaderNativePopPolicy.isPop(from: source, to: transition.viewController(forKey: .to),
            in: navigation, isInteractive: transition.isInteractive)
        NavigationTrace.shared.mark("pop",
            "willDisappear interactive=\(transition.isInteractive) isPop=\(isPop)")
        guard isPop else { return }
        // 转场开始时**不**释放 tab chrome。
        //
        // 日志证据：在 pop 起点释放后 100 ms 内就会出现 cancelled=true，
        // 于是 acquire 又把栏藏回去——一次没滑够距离的侧滑会让整条栏
        // 「出现→消失」闪一遍。改成只在转场确认提交（非取消）后才释放，
        // 取消的手势全程零变化。
        transition.animate(alongsideTransition: nil) { [weak self] context in
            NavigationTrace.shared.mark("pop", "pop 结束 cancelled=\(context.isCancelled)"
                + (context.isCancelled ? "（未归还 tab bar）" : "（归还 tab bar）"))
            guard let self, !context.isCancelled else { return }
            self.prepareForExit()
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // A cancelled interactive pop reappears even if UIKit could not register
        // another transition completion. Reacquiring an owned token is idempotent.
        if hasPreparedExit { finishExit(cancelled: true) }
    }

    func prepareForExit() {
        guard !hasPreparedExit else { return }
        hasPreparedExit = true
        onLeaving()
    }

    func finishExit(cancelled: Bool) {
        guard hasPreparedExit else { return }
        hasPreparedExit = false
        if cancelled { onCancelled() }
    }

    private func belongs(to controller: UIViewController) -> Bool {
        var ancestor: UIViewController? = self
        while let candidate = ancestor {
            if candidate === controller { return true }
            ancestor = candidate.parent
        }
        return false
    }
}
