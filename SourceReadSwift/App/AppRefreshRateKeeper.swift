import SwiftUI
import UIKit
import QuartzCore

/// Bounded, explicit comparison with the old refresh driver; ordinary UI uses adaptive cadence.
final class AppRefreshRateKeeper: UIView {
    static let diagnosticDefaultsKey = "developer.legacyRefreshKeeper"
    static let maximumDiagnosticDuration: TimeInterval = 30
    private var link: CADisplayLink?
    private var deadline: DispatchWorkItem?
    private var isEnabled = false
    private let caDriverLayer = CALayer()
    private static let pulseAnimationKey = "com.edc21.SourceReadSwift.proMotionPulse"

    private(set) static var currentHeldRate: Float = 0

    var isHolding: Bool { link != nil }
    private(set) var heldRate: Float = 0
    private var observingResume = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
        caDriverLayer.frame = CGRect(x: 0, y: 0, width: 2, height: 2)
        caDriverLayer.backgroundColor = UIColor(white: 0.5, alpha: 1.0).cgColor
        caDriverLayer.opacity = 0.008
        layer.addSublayer(caDriverLayer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func maximumRate() -> Float {
        let screenRate = window?.windowScene?.screen.maximumFramesPerSecond ?? UIScreen.main.maximumFramesPerSecond
        return Float(min(screenRate, ProcessInfo.processInfo.isLowPowerModeEnabled ? 60 : 120))
    }

    private var isContinuousMode = false

    func start(duration: TimeInterval = AppRefreshRateKeeper.maximumDiagnosticDuration) {
        isEnabled = true
        isContinuousMode = !duration.isFinite
        deadline?.cancel()
        deadline = nil
        if duration.isFinite {
            let expiry = DispatchWorkItem { [weak self] in self?.finishDiagnostic() }
            deadline = expiry
            let boundedDuration = min(max(duration, 0.01), Self.maximumDiagnosticDuration)
            DispatchQueue.main.asyncAfter(deadline: .now() + boundedDuration, execute: expiry)
        }
        updateCadenceIfNeeded()
    }

    func startContinuous() {
        start(duration: .infinity)
    }

    private func updateCadenceIfNeeded() {
        guard isEnabled, window != nil,
              UIApplication.shared.applicationState != .background else { return }
        let rate = maximumRate()
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
        let displayLink = CADisplayLink(target: CadenceTarget(),
                                        selector: #selector(CadenceTarget.tick))
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
        guard caDriverLayer.animation(forKey: Self.pulseAnimationKey) == nil else { return }
        let animation = CABasicAnimation(keyPath: "transform.translation.x")
        animation.fromValue = 0.0
        animation.toValue = 0.5
        animation.duration = 0.5
        animation.autoreverses = true
        animation.repeatCount = .greatestFiniteMagnitude
        animation.isRemovedOnCompletion = false
        if #available(iOS 15.0, *) {
            animation.preferredFrameRateRange = CAFrameRateRange(
                minimum: rate, maximum: rate, preferred: rate
            )
        }
        caDriverLayer.add(animation, forKey: Self.pulseAnimationKey)
    }

    func stop() {
        isEnabled = false
        deadline?.cancel()
        deadline = nil
        caDriverLayer.removeAnimation(forKey: Self.pulseAnimationKey)
        link?.invalidate()
        link = nil
        heldRate = 0
        Self.currentHeldRate = 0
    }

    @objc private func finishDiagnostic() {
        if isContinuousMode {
            caDriverLayer.removeAnimation(forKey: Self.pulseAnimationKey)
            link?.invalidate()
            link = nil
            heldRate = 0
            Self.currentHeldRate = 0
            return
        }
        stop()
        UserDefaults.standard.set(false, forKey: Self.diagnosticDefaultsKey)
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            if isContinuousMode {
                caDriverLayer.removeAnimation(forKey: Self.pulseAnimationKey)
                link?.invalidate()
                link = nil
                heldRate = 0
                Self.currentHeldRate = 0
            } else {
                finishDiagnostic()
            }
        } else {
            updateCadenceIfNeeded()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if window != nil, heldRate != maximumRate() {
            updateCadenceIfNeeded()
        }
    }

    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        guard !observingResume else { return }
        observingResume = true
        NotificationCenter.default.addObserver(
            self, selector: #selector(finishDiagnostic), name: UIApplication.willResignActiveNotification, object: nil
        )
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
        updateCadenceIfNeeded()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        deadline?.cancel()
        link?.invalidate()
    }
}

private final class CadenceTarget: NSObject {
    // The compositor animates its driver layer. A new main-thread
    // CATransaction on every tick would compete with scrolling and glass.
    @objc func tick() {}
}

struct AppRefreshRateKeeperView: UIViewRepresentable {
    var enabled: Bool = true

    func makeUIView(context: Context) -> AppRefreshRateKeeper {
        let view = AppRefreshRateKeeper()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        if enabled { view.startContinuous() }
        return view
    }

    func updateUIView(_ view: AppRefreshRateKeeper, context: Context) {
        if enabled { view.startContinuous() } else { view.stop() }
    }

    static func dismantleUIView(_ view: AppRefreshRateKeeper, coordinator: ()) {
        view.stop()
    }
}
