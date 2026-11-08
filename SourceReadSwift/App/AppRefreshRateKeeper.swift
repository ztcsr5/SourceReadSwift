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

    func start() {
        guard link == nil else { return }
        // 必须从所在场景的屏幕取上限：UIScreen.main 在新系统上可能返回 60，
        // 那样就会一直按 60 要帧，看起来「常驻 120 没生效」。
        let screen = window?.windowScene?.screen ?? UIScreen.main
        let rate = min(Float(screen.maximumFramesPerSecond), 120)
        let displayLink = CADisplayLink(target: WeakProxy(target: self),
                                        selector: #selector(WeakProxy.tick))
        if #available(iOS 15.0, *) {
            displayLink.preferredFrameRateRange = CAFrameRateRange(
                minimum: rate, maximum: rate, preferred: rate
            )
        }
        displayLink.add(to: .main, forMode: .common)
        link = displayLink
    }

    func stop() {
        link?.invalidate()
        link = nil
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { stop() } else { start() }
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
