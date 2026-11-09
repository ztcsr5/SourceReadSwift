import SwiftUI
import UIKit
import QuartzCore

/// 全应用把屏幕刷新率钉在设备上限（ProMotion 120Hz）。
///
/// iOS 的 ProMotion 是自适应的：没有持续要帧的请求时，系统会把刷新率降到 60/30/24。
/// 只要有一个以最高刷新率运行的 CADisplayLink 主线程在跑，系统就会一直按最高档排帧，
/// 于是触摸起手不再出现 60 → 120 的爬坡。
///
/// 挂在 App 根视图上常驻运行。代价是耗电（屏幕多刷一倍），按产品决策接受。
final class AppRefreshRateKeeper: UIView {
    private var link: CADisplayLink?

    var isHolding: Bool { link != nil }
    private(set) var heldRate: Float = 0
    private var observingResume = false

    /// 从所有已连接场景里取最大的屏幕刷新率：
    /// `UIScreen.main` 在新系统上可能返回 60，单看它会把上限误判成 60。
    private static func maximumRate() -> Float {
        let rates = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .map { Float($0.screen.maximumFramesPerSecond) }
        let value = rates.max() ?? Float(UIScreen.main.maximumFramesPerSecond)
        return min(max(value, 60), 120)
    }

    func start() {
        let rate = Self.maximumRate()
        // `makeUIView` can run before the scene is attached, where the screen
        // still reports 60 Hz. Once `didMoveToWindow` runs the real screen is
        // known, so restart the link instead of keeping the launch-time rate
        // for the rest of the session.
        if let link {
            if abs(link.preferredFrameRateRange.maximum - rate) < 0.5 { return }
            link.invalidate()
            self.link = nil
            heldRate = 0
        }
        let displayLink = CADisplayLink(target: WeakProxy(target: self),
                                        selector: #selector(WeakProxy.tick))
        if #available(iOS 15.0, *) {
            displayLink.preferredFrameRateRange = CAFrameRateRange(
                minimum: rate, maximum: rate, preferred: rate
            )
        }
        displayLink.add(to: .main, forMode: .common)
        link = displayLink
        heldRate = rate
        #if DEBUG
        accessibilityValue = String(Int(rate))
        #endif
    }

    func stop() {
        link?.invalidate()
        link = nil
        heldRate = 0
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { stop() } else { start() }
    }

    /// 回到前台后系统会重新排帧，必须重新要一次 120，否则会停在 60。
    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        guard !observingResume else { return }
        observingResume = true
        NotificationCenter.default.addObserver(
            self, selector: #selector(resume), name: UIApplication.didBecomeActiveNotification, object: nil
        )
    }

    @objc private func resume() {
        stop()
        start()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

/// 避免 CADisplayLink 强引用 target 形成循环。
private final class WeakProxy: NSObject {
    weak var target: AnyObject?
    init(target: AnyObject) { self.target = target }
    @objc func tick() {
        // 空实现：链接本身的存在就是"持续要帧"的信号。
    }
}

/// 把 keeper 挂进 SwiftUI 层级；根视图挂一次即可全应用生效。
struct AppRefreshRateKeeperView: UIViewRepresentable {
    var enabled: Bool = true

    func makeUIView(context: Context) -> AppRefreshRateKeeper {
        let view = AppRefreshRateKeeper()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        if enabled { view.start() }
        return view
    }

    func updateUIView(_ view: AppRefreshRateKeeper, context: Context) {
        if enabled { view.start() } else { view.stop() }
    }

    static func dismantleUIView(_ view: AppRefreshRateKeeper, coordinator: ()) {
        view.stop()
    }
}
