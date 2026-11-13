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
    private let pulseLayer = CALayer()
    private var pulsePhase = false
    private static let pulseAnimationKey = "com.edc21.SourceReadSwift.proMotionPulse"

    private(set) static var currentHeldRate: Float = 0

    var isHolding: Bool { link != nil }
    private(set) var heldRate: Float = 0
    private var observingResume = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
        pulseLayer.frame = CGRect(x: 0, y: 0, width: 1, height: 1)
        pulseLayer.backgroundColor = UIColor(white: 1, alpha: 0.004).cgColor
        pulseLayer.opacity = 0.004
        layer.addSublayer(pulseLayer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private var isSimulatorRuntime: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }

    private func maximumRate() -> Float {
        if isSimulatorRuntime {
            let windowRate = Float(window?.windowScene?.screen.maximumFramesPerSecond ?? 0)
            let sceneRates = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .map { Float($0.screen.maximumFramesPerSecond) }
            let mainRate = Float(UIScreen.main.maximumFramesPerSecond)
            let value = max(windowRate, max(sceneRates.max() ?? 0, mainRate))
            return min(max(value, 60), 120)
        }
        return 120
    }

    func start() {
        let rate = maximumRate()
        if isSimulatorRuntime {
            heldRate = rate
            Self.currentHeldRate = rate
            #if DEBUG
            accessibilityValue = String(Int(rate))
            #endif
            return
        }
        if let link {
            if abs(link.preferredFrameRateRange.maximum - rate) < 0.5,
               abs(link.preferredFrameRateRange.minimum - rate) < 0.5 {
                installPulseAnimationIfNeeded(rate: rate)
                return
            }
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
        installPulseAnimationIfNeeded(rate: rate)
        #if DEBUG
        accessibilityValue = String(Int(rate))
        #endif
    }

    private func installPulseAnimationIfNeeded(rate: Float) {
        guard pulseLayer.animation(forKey: Self.pulseAnimationKey) == nil else { return }
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = 0.004
        animation.toValue = 0.008
        animation.duration = 1.0
        animation.autoreverses = true
        animation.repeatCount = .greatestFiniteMagnitude
        animation.isRemovedOnCompletion = false
        if #available(iOS 15.0, *) {
            animation.preferredFrameRateRange = CAFrameRateRange(
                minimum: rate, maximum: rate, preferred: rate
            )
        }
        pulseLayer.add(animation, forKey: Self.pulseAnimationKey)
    }

    func stop() {
        pulseLayer.removeAnimation(forKey: Self.pulseAnimationKey)
        link?.invalidate()
        link = nil
        heldRate = 0
        Self.currentHeldRate = 0
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { stop() } else { start() }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if window != nil, heldRate < maximumRate() {
            start()
        }
    }

    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        guard !observingResume else { return }
        observingResume = true
        NotificationCenter.default.addObserver(
            self, selector: #selector(resume), name: UIApplication.didBecomeActiveNotification, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(resume), name: UIScene.didActivateNotification, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(resume), name: UIWindow.didBecomeKeyNotification, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(resume), name: Notification.Name.NSProcessInfoPowerStateDidChange, object: nil
        )
    }

    @objc private func resume() {
        stop()
        start()
    }

    fileprivate func handleDisplayTick() {
        if heldRate < 120 {
            let desired = maximumRate()
            if desired > heldRate {
                start()
            }
        }
        pulsePhase.toggle()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        pulseLayer.opacity = pulsePhase ? 0.008 : 0.004
        CATransaction.commit()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        link?.invalidate()
    }
}

private final class WeakProxy: NSObject {
    weak var target: AppRefreshRateKeeper?
    init(target: AppRefreshRateKeeper) { self.target = target }
    @objc func tick() { target?.handleDisplayTick() }
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
