import SwiftUI
import UIKit
import QuartzCore

/// 闃呰椤靛唴鎶婂睆骞曞埛鏂扮巼閽夊湪璁惧涓婇檺锛圥roMotion 120Hz锛夈€?///
/// iOS 鐨?ProMotion 鏄嚜閫傚簲鐨勶細闈欐鎴栧垰鍒氳捣鎵嬫椂绯荤粺鎸?60Hz 鎺掑抚锛?/// 浜庢槸婊氬姩鐨勫ご鍑犲抚浼氫粠 60 鐖埌 120锛屼綋鎰熷氨鏄?璧锋墜涓嶈窡鎵?銆?/// 鍙鏈変竴涓互鏈€楂樺埛鏂扮巼杩愯鐨?CADisplayLink 鍦ㄨ窇锛岀郴缁熷氨浼氫竴鐩存寜鏈€楂樻。鎺掑抚銆?///
/// 浠ｄ环鏄€楃數锛堝睆骞曞鍒蜂竴鍊嶏級锛屽洜姝ゅ彧鍦ㄩ槄璇婚〉鍙鏈熼棿杩愯锛岀寮€鍗抽噴鏀俱€?final class ReaderRefreshRateKeeper: UIView {
    private var link: CADisplayLink?

    var isHolding: Bool { link != nil }

    func start() {
        guard link == nil else { return }
        let displayLink = CADisplayLink(target: WeakProxy(target: self), selector: #selector(WeakProxy.tick))
        // 鍙湪鏈満鏀寔 120Hz 鏃惰姹?120锛屽叾浣欒澶囨部鐢ㄧ郴缁熶笂闄愩€?        let maximum = Float(UIScreen.main.maximumFramesPerSecond)
        let rate = min(maximum, 120)
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

    @objc private func tick() {
        // 绌哄疄鐜帮細鐩殑鍙槸璁╃郴缁熸寔缁帓鏈€楂樺抚鐜囥€?    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { stop() }
    }
}

/// 閬垮厤 CADisplayLink 寮哄紩鐢?target 褰㈡垚寰幆銆?private final class WeakProxy: NSObject {
    weak var target: AnyObject?
    init(target: AnyObject) { self.target = target }
    @objc func tick() {
        // 杞彂涓嶉渶瑕佸弬鏁帮紝target 瀛樺湪鍗宠鏄庨摼鎺ヤ粛鏈夋晥銆?    }
}

/// 鎶?keeper 鎸傝繘 SwiftUI 灞傜骇鐨勫涓昏鍥俱€?struct ReaderRefreshRateKeeperView: UIViewRepresentable {
    var enabled: Bool = true

    func makeUIView(context: Context) -> ReaderRefreshRateKeeper {
        let view = ReaderRefreshRateKeeper()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        if enabled { view.start() }
        return view
    }

    func updateUIView(_ view: ReaderRefreshRateKeeper, context: Context) {
        if enabled { view.start() } else { view.stop() }
    }

    static func dismantleUIView(_ view: ReaderRefreshRateKeeper, coordinator: ()) {
        view.stop()
    }
}
