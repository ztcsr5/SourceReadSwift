import SwiftUI
import UIKit
import OSLog

/// Native edge return is the sole prose exit. Paged modes still reserve only
/// the leading edge for navigation; their page pan remains inside the content.
enum ReaderSystemReturnPolicy {
    static func isEnabled(isScroll: Bool, menuVisible: Bool, blocked: Bool, selectionEnabled: Bool) -> Bool {
        _ = isScroll
        _ = menuVisible
        return !blocked && !selectionEnabled
    }
}

enum ReaderExitSwipePolicy {
    /// 滚动模式下菜单不可见时仍要能用左缘右滑退出——这正是阅读中唯一的返回手势。
    static func isEnabled(menuVisible: Bool, settingsVisible: Bool, coverPresented: Bool,
                          scrollMode: Bool = false) -> Bool {
        guard !settingsVisible, !coverPresented else { return false }
        return menuVisible || scrollMode
    }

    static func isRightward(_ movement: CGPoint) -> Bool {
        movement.x.isFinite && movement.y.isFinite
            && movement.x > 0 && movement.x > abs(movement.y) * 1.5
    }

    static func isProseFallbackEnabled(reducesMotion: Bool, allowsBookReturn: Bool) -> Bool {
        reducesMotion && allowsBookReturn
    }

    static func isSystemReturnActive(_ state: UIGestureRecognizer.State) -> Bool {
        state == .began || state == .changed || state == .ended
    }

    static func shouldFinish(translation: CGPoint, velocity: CGPoint, width: CGFloat) -> Bool {
        guard width.isFinite, width > 0, isRightward(translation) else { return false }
        let threshold = max(72, min(width * 0.22, 140))
        return translation.x >= threshold
            || (translation.x >= 32 && isRightward(velocity) && velocity.x >= 650)
    }
}

/// The leading strip belongs to the system pop gesture. A tap or short drag
/// that starts here must not reach the page/menu tap zones; 24 pt was narrower
/// than a finger contact and made a light edge touch flash the reader menu.
enum ReaderEdgeTapPolicy {
    static let reservedLeadingWidth: CGFloat = 44

    static func isReserved(_ location: CGPoint) -> Bool {
        location.x.isFinite && location.x <= reservedLeadingWidth
    }
}

/// Only the reader's hosting subtree receives the recognizer, never the window.
/// Only allowed prose/menu routes enable it; page turns and selection remain protected.
struct ReaderExitSwipeBridge: UIViewControllerRepresentable {
    let enabled: Bool
    let onExit: () -> Void
    var prefersSystemReturn = false
    /// 拖拽过程中的实时位移（正数 = 向右）。覆盖层用它驱动跟手动画。
    var onChanged: (CGFloat) -> Void = { _ in }
    /// 松手时的原始位移、速度与「是否为系统取消」。
    /// 判定交给覆盖层，保持策略单一来源；系统取消必须走取消恢复，不能当正常松手。
    var onEnded: (CGFloat, CGFloat, Bool) -> Void = { _, _, _ in }

    func makeUIViewController(context: Context) -> ReaderExitSwipeController {
        let controller = ReaderExitSwipeController()
        controller.configure(enabled: enabled, prefersSystemReturn: prefersSystemReturn,
                             onExit: onExit, onChanged: onChanged, onEnded: onEnded)
        return controller
    }

    func updateUIViewController(_ controller: ReaderExitSwipeController, context: Context) {
        controller.configure(enabled: enabled, prefersSystemReturn: prefersSystemReturn,
                             onExit: onExit, onChanged: onChanged, onEnded: onEnded)
    }

    static func dismantleUIViewController(_ controller: ReaderExitSwipeController, coordinator: ()) {
        controller.detach()
    }
}

final class ReaderExitSwipeController: UIViewController, UIGestureRecognizerDelegate {
    private static let decisions = Logger(subsystem: "com.edc21.SourceReadSwift.book-passage", category: "gesture")
    private(set) var exitEnabled = false
    private var didExit = false
    private var prefersSystemReturn = false
    private var onExit: () -> Void = {}
    private var onChanged: (CGFloat) -> Void = { _ in }
    private var onEnded: (CGFloat, CGFloat, Bool) -> Void = { _, _, _ in }
    /// 本次手势是否被判定为纵向滚动（纵向占优时放弃返回，交给翻页/滚动）。
    private var verticalDominant = false
    private(set) weak var prioritizedNavigationEdge: UIGestureRecognizer?
    #if DEBUG
    private(set) var fallbackMotionCount = 0
    private var isFallbackGestureActive = false
    private var recordedFallbackMovement = false
    #endif
    lazy var edgePan: UIScreenEdgePanGestureRecognizer = {
        let gesture = UIScreenEdgePanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        gesture.edges = .left
        gesture.name = "reader.menuSwipeExit"
        gesture.maximumNumberOfTouches = 1
        gesture.delegate = self
        gesture.isEnabled = false
        return gesture
    }()

    override func loadView() {
        view = UIView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        #if DEBUG
        view.isAccessibilityElement = true
        view.accessibilityIdentifier = "reader.fallbackGestureEvidence"
        view.accessibilityLabel = "阅读器兜底返回输入"
        view.accessibilityValue = "0"
        #endif
    }

    func configure(enabled: Bool, prefersSystemReturn: Bool = false,
                   onExit: @escaping () -> Void,
                   onChanged: @escaping (CGFloat) -> Void = { _ in },
                   onEnded: @escaping (CGFloat, CGFloat, Bool) -> Void = { _, _, _ in }) {
        exitEnabled = enabled
        self.prefersSystemReturn = prefersSystemReturn
        self.onExit = onExit
        self.onChanged = onChanged
        self.onEnded = onEnded
        if !enabled { didExit = false }
        if isViewLoaded { attachIfNeeded() }
    }

    override func didMove(toParent parent: UIViewController?) {
        super.didMove(toParent: parent)
        if parent == nil { detach() } else { attachIfNeeded() }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        attachIfNeeded()
        if prefersSystemReturn {
            Self.decisions.notice("READY native=\(self.usesSystemReturn ? 1 : 0, privacy: .public) fallback=\(self.edgePan.isEnabled ? 1 : 0, privacy: .public)")
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        attachIfNeeded()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        detach()
    }

    private var usesSystemReturn: Bool {
        if #available(iOS 18.0, *), prefersSystemReturn,
           let navigation = navigationController, navigation.viewControllers.count > 1 {
            #if compiler(>=6.2)
            if #available(iOS 26.0, *), navigation.interactiveContentPopGestureRecognizer?.isEnabled == true { return true }
            #endif
            return navigation.interactivePopGestureRecognizer?.isEnabled == true
        }
        return false
    }

    private func attachIfNeeded() {
        let needsFallback = exitEnabled
        if edgePan.isEnabled != needsFallback { edgePan.isEnabled = needsFallback }
        guard let host = parent?.view, host !== view else { return }
        if edgePan.view !== host {
            edgePan.view?.removeGestureRecognizer(edgePan)
            host.addGestureRecognizer(edgePan)
        }
        if prefersSystemReturn, let nativeEdge = navigationController?.interactivePopGestureRecognizer,
           nativeEdge !== prioritizedNavigationEdge {
            // An enabled native recognizer gets first refusal; only its actual
            // failure releases this fallback. Never wait on full-content pop.
            edgePan.require(toFail: nativeEdge)
            prioritizedNavigationEdge = nativeEdge
        }
    }

    func detach() {
        edgePan.view?.removeGestureRecognizer(edgePan)
    }

    private var hasActiveSystemReturn: Bool {
        if let pop = navigationController?.interactivePopGestureRecognizer,
           ReaderExitSwipePolicy.isSystemReturnActive(pop.state) { return true }
        #if compiler(>=6.2)
        if #available(iOS 26.0, *), let pop = navigationController?.interactiveContentPopGestureRecognizer,
           ReaderExitSwipePolicy.isSystemReturnActive(pop.state) { return true }
        #endif
        return false
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard exitEnabled, !didExit, gestureRecognizer === edgePan, !hasActiveSystemReturn else {
            NavigationTrace.shared.mark("GEST", "shouldBegin 拒绝：enabled=\(exitEnabled) didExit=\(didExit) system=\(hasActiveSystemReturn)")
            return false
        }
        // 不再用瞬时速度判定方向。
        // `.began` 那一刻速度常常是 0 或噪声，isRightward 会随机为 false，
        // 表现就是「有时完全没反应」。方向改在 `.changed` 里判断：
        // 纵向占优就当取消，横向右才驱动转场，横向左直接忽略。
        NavigationTrace.shared.mark("GEST", "shouldBegin 允许")
        return true
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard exitEnabled, !didExit, view.window != nil,
              view.bounds.contains(touch.location(in: view)),
              parent?.presentedViewController == nil else { return false }
        // 只接真正的左缘窄条（<32pt）。这是**收窄**，不是放宽：
        // 正文中部的横向翻页不进入这个区域，因此返回手势不会抢翻页。
        let location = touch.location(in: edgePan.view)
        guard location.x <= 32 else {
            NavigationTrace.shared.breadcrumb("GEST", "shouldReceive 忽略 x=\(Int(location.x))")
            return false
        }
        var candidate = touch.view
        while let touched = candidate {
            if touched is UIControl { return false }
            if touched === edgePan.view { break }
            candidate = touched.superview
        }
        return true
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        // 这里曾经对所有后代识别器返回 true。
        // 该方法的语义是「**我**是否必须等对方失败」，返回 true 等于让退出手势
        // 排队等 WKWebView 的 pan 失败——而滚动 pan 往往要到手指抬起才失败，
        // 于是退出几乎永远起不来；只有在 WebView pan 恰好快速失败（横向占优）时
        // 才偶然生效。这就是「时灵时不灵」的直接原因。
        //
        // 返回 false：边缘手势不服从后代识别器。是否会抢翻页由 shouldReceive 的
        // 32pt 边缘带守住，与优先级无关。
        if otherGestureRecognizer === navigationController?.interactivePopGestureRecognizer { return false }
        #if compiler(>=6.2)
        if #available(iOS 26.0, *), otherGestureRecognizer === navigationController?.interactiveContentPopGestureRecognizer { return false }
        #endif
        if gestureRecognizer === edgePan, otherGestureRecognizer !== edgePan {
            NavigationTrace.shared.breadcrumb("GEST", "不服从 \(type(of: otherGestureRecognizer))")
        }
        return false
    }

    @objc private func handlePan(_ gesture: UIScreenEdgePanGestureRecognizer) {
        #if DEBUG
        switch gesture.state {
        case .began:
            isFallbackGestureActive = true
            recordedFallbackMovement = false
        case .changed:
            if isFallbackGestureActive, !recordedFallbackMovement, gesture.numberOfTouches > 0 {
                recordedFallbackMovement = true
                fallbackMotionCount += 1
                view.accessibilityValue = String(fallbackMotionCount)
            }
        case .ended, .cancelled, .failed:
            isFallbackGestureActive = false
            recordedFallbackMovement = false
        default: break
        }
        #endif

        // 实时位移交给覆盖层做跟手动画。只在真正可退出的路径上发。
        if gesture.state == .began {
            verticalDominant = false
            let t = gesture.translation(in: gesture.view)
            NavigationTrace.shared.mark("GEST", "began t=(\(Int(t.x)),\(Int(t.y)))")
            return
        }
        if gesture.state == .changed {
            let t = gesture.translation(in: gesture.view)
            let v = gesture.velocity(in: gesture.view)
            // 纵向占优即视为滚动，不驱动返回，也不抢翻页。
            if !verticalDominant, abs(t.y) > abs(t.x) {
                verticalDominant = true
                NavigationTrace.shared.mark("GEST", "纵向占优 → 放弃返回 t=(\(Int(t.x)),\(Int(t.y)))")
            }
            guard exitEnabled, !hasActiveSystemReturn, !verticalDominant, t.x > 0 else { return }
            NavigationTrace.shared.breadcrumb("GEST", "changed dx=\(Int(t.x)) vx=\(Int(v.x))")
            onChanged(t.x)
            return
        }
        guard gesture.state == .ended || gesture.state == .cancelled || gesture.state == .failed else { return }

        let translation = gesture.translation(in: gesture.view)
        let velocity = gesture.velocity(in: gesture.view)
        let wasCancelled = (gesture.state == .cancelled || gesture.state == .failed)
        let reason: String
        if wasCancelled { reason = "系统取消" }
        else if verticalDominant { reason = "纵向占优" }
        else if velocity.x < -820 { reason = "反向甩动" }
        else { reason = "正常松手" }
        NavigationTrace.shared.mark("GEST",
            "\(gesture.state == .ended ? "ended" : "cancelled") dx=\(Int(translation.x)) vx=\(Int(velocity.x)) → \(reason)")
        onEnded(translation.x, velocity.x, wasCancelled || verticalDominant)
        // 系统取消必须走取消恢复，不能被当成正常松手。
        guard gesture.state == .ended, !wasCancelled, !verticalDominant else { return }
        // 兼容既有调用方（ReaderView 仍依赖桥自己判定后 onExit）。
        // 覆盖层把 onExit 传成空闭包，改由 onEnded 驱动动画与关闭。
        completeSwipe(translation: translation, velocity: velocity, cancelled: false)
    }

    func completeSwipe(translation: CGPoint, velocity: CGPoint, cancelled: Bool) {
        guard exitEnabled, edgePan.isEnabled, !didExit, !cancelled, !hasActiveSystemReturn,
              ReaderExitSwipePolicy.shouldFinish(translation: translation, velocity: velocity,
                                                width: edgePan.view?.bounds.width ?? 0) else { return }
        didExit = true
        onExit()
    }
}
