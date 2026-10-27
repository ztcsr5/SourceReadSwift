import CoreGraphics
import Foundation

/// 阅读器安全区解析。
///
/// 阅读页根视图用 `.ignoresSafeArea()` 做全屏铺底，SwiftUI 的 `safeAreaInsets`
/// 在这一层已经是 0；而 `UIWindow.safeAreaInsets` 在 LiveContainer、侧载容器、
/// 悬浮窗或部分分屏环境里也可能上报 0。这里统一做三件事：
/// 1. 取所有窗口安全区的最大值，而不是只看 key window；
/// 2. 用状态栏高度兜底，状态栏可见时一定有高度；
/// 3. 两者都为 0 时按屏幕尺寸给出该机型的实测安全区。
enum ReaderSafeAreaResolver {
    struct Insets: Equatable {
        let top: CGFloat
        let bottom: CGFloat
    }

    static func resolve(
        windowTop: CGFloat,
        windowBottom: CGFloat,
        statusBarHeight: CGFloat,
        screenSize: CGSize
    ) -> Insets {
        var top = max(max(windowTop, statusBarHeight), 0)
        if top < 1 {
            top = fallbackTop(for: screenSize)
        }
        var bottom = max(windowBottom, 0)
        if bottom < 1, top >= 44 {
            bottom = 34
        }
        return Insets(top: top, bottom: bottom)
    }

    /// 仅用于窗口与状态栏都上报 0 的容器环境；数值来自各代 iPhone 实测。
    static func fallbackTop(for screenSize: CGSize) -> CGFloat {
        let width = screenSize.width
        let height = screenSize.height
        // 横屏时刘海在侧边，顶部安全区是 0，不能套用竖屏表。
        if height < width { return 0 }
        if height >= 930 { return 59 }   // 14 Pro Max / 15 Pro Max / 16 Plus
        if height >= 920 { return 47 }   // 12/13 Pro Max、14 Plus
        if height >= 890 { return 44 }   // XR / 11 / XS Max
        if height >= 850 { return 59 }   // 14 Pro / 15 / 15 Pro / 16
        if height >= 840 { return 47 }   // 12 / 13 / 14
        if height >= 810 { return width <= 375 ? 50 : 44 } // 12 mini / X / XS / 11 Pro
        return 20                        // SE / 8 及以下
    }
}
