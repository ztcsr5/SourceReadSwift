import SwiftUI
import UIKit

/// 覆盖层过渡的取值策略。
///
/// 单独成类型是为了能单测：几何用插值还是直接赋值、松手是否算完成，
/// 都是纯函数，不需要 UI 就能验证。
enum ReaderTransitionPolicy {
    /// 跟手进度：手指右移多少，阅读层就退出多少。
    /// 0 = 完全展开，1 = 已经退回封面。
    static func dismissalProgress(translation: CGFloat, width: CGFloat) -> CGFloat {
        guard width > 0 else { return 0 }
        return min(max(translation / width, 0), 1)
    }

    /// 松手判定：距离过半，或速度足够快，都算完成退出。
    /// 反向速度（往左甩）一律算取消，避免"想收回去却被丢出去"。
    static func shouldDismiss(translation: CGFloat, velocity: CGFloat, width: CGFloat) -> Bool {
        guard width > 0 else { return false }
        if velocity > 820 { return true }
        if velocity < -820 { return false }
        return translation > max(96, width * 0.32)
    }

    /// 收缩后的阅读层几何：从封面矩形插值到全屏。
    static func targetRect(cover: CGRect, screen: CGSize, progress: CGFloat) -> CGRect {
        let p = min(max(progress, 0), 1)
        let width = cover.width + (screen.width - cover.width) * p
        let height = cover.height + (screen.height - cover.height) * p
        let centerX = cover.midX + (screen.width / 2 - cover.midX) * p
        let centerY = cover.midY + (screen.height / 2 - cover.midY) * p
        return CGRect(x: centerX - width / 2, y: centerY - height / 2, width: width, height: height)
    }

    static func cornerRadius(progress: CGFloat, compact: CGFloat = 10, full: CGFloat = 0) -> CGFloat {
        compact + (full - compact) * min(max(progress, 0), 1)
    }

    /// 正文只在几何基本落位后才出现，避免"文字跟着缩放"的廉价感。
    static func contentOpacity(progress: CGFloat) -> Double {
        let p = min(max(progress, 0), 1)
        guard p > 0.62 else { return 0 }
        return Double((p - 0.62) / 0.38)
    }

    /// 封面在阅读层里淡出，由正文接管。
    static func coverOpacity(progress: CGFloat) -> Double {
        let p = min(max(progress, 0), 1)
        guard p < 0.72 else { return 0 }
        return Double(1 - p / 0.72)
    }
}

/// 驱动一次进入/退出的进度。跟手时直接改 progress，松手后补一段动画。
@MainActor
final class ReaderTransition: ObservableObject {
    /// 0 = 停在封面位置，1 = 全屏阅读。
    @Published var progress: CGFloat
    @Published var isDismissing = false

    var reducesMotion: Bool
    private let openDuration: Double = 0.34

    init(reducesMotion: Bool, startsOpen: Bool = false) {
        self.reducesMotion = reducesMotion
        self.progress = startsOpen ? 1 : 0
    }

    var openAnimation: Animation? {
        reducesMotion ? nil : .interactiveSpring(response: openDuration, dampingFraction: 0.86)
    }

    var settleAnimation: Animation? {
        reducesMotion ? nil : .interactiveSpring(response: 0.30, dampingFraction: 0.92)
    }

    func open() {
        withAnimation(openAnimation) { progress = 1 }
    }

    /// 跟手：不带动画，直接赋值。
    func drag(translation: CGFloat, width: CGFloat) {
        progress = 1 - ReaderTransitionPolicy.dismissalProgress(translation: translation, width: width)
    }

    /// 松手：完成就继续退到底，取消就弹回全屏。
    func endDrag(finish: Bool, onFinish: @escaping () -> Void) {
        withAnimation(settleAnimation) {
            progress = finish ? 0 : 1
            if finish { isDismissing = true }
        }
        if finish {
            // 等动画落位再移除，避免中途闪一帧主页。
            let delay = reducesMotion ? 0 : 0.20
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: onFinish)
        }
    }
}
