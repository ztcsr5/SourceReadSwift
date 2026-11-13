import SwiftUI
import UIKit
import QuartzCore

/// 全应用锁定设备物理最高刷新率（ProMotion 120Hz），不计较功耗、不随省电模式降频。
///
/// iOS ProMotion 采用按需升频策略：无持续高刷请求时会自动退回 60Hz/30Hz/24Hz，导致滑卡、
/// 点按与阅读滚动起手的前几帧出现掉帧阶跃。挂在根视图常驻 120Hz `CADisplayLink`
/// 并配置 `CAFrameRateRange(min: rate, max: rate, preferred: rate)`，使系统渲染管线
/// 全天候维持满帧排帧。
final class AppRefreshRateKeeper: UIView {
    private var link: CADisplayLink?

    private(set) static var currentHeldRate: Float = 0

    var isHolding: Bool { link != nil }
    private(set) var heldRate: Float = 0
    private var observingResume = false

    private static func maximumRate() -> Float {
        let rates = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .map { Float($0.screen.maximumFramesPerSecond) }
        let value = rates.max() ?? Float(UIScreen.main.maximumFramesPerSecond)
        return min(max(value, 60), 120)
    }

    func start() {
        let rate = Self.maximumRate()
        if let link {
            if abs(link.preferredFrameRateRange.maximum - rate) < 0.5,
               abs(link.preferredFrameRateRange.minimum - rate) < 0.5 { return }
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
        Self.currentHeldRate = rate
        #if DEBUG
        accessibilityValue = String(Int(rate))
        #endif
    }

    func stop() {
        link?.invalidate()
        link = nil
        heldRate = 0
        Self.currentHeldRate = 0
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { stop() } else { start() }
    }

    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        guard !observingResume else { return }
        observingResume = true
        NotificationCenter.default.addObserver(
            self, selector: #selector(resume), name: UIApplication.didBecomeActiveNotification, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(resume), name: Notification.Name.NSProcessInfoPowerStateDidChange, object: nil
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

private final class WeakProxy: NSObject {
    weak var target: AnyObject?
    init(target: AnyObject) { self.target = target }
    @objc func tick() {}
}

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
