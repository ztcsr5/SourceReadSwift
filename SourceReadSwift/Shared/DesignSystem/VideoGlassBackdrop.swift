import SwiftUI

/// 「视频玻璃」主题的动态背景。
///
/// 需求是可动的渐变（像视频一样持续流动），但不能真的播视频：
/// 解码视频会持续占用解码器和电量，滚动时还会跟主线程抢带宽。
/// 这里用三团 `RadialGradient`（外圈透明，所以不需要 `blur`，代价远低于
/// 大面积实时模糊）沿不同周期缓慢漂移，视觉上就是流动的极光/余烬。
///
/// 帧率刻意压到 20 Hz：主题背景是低频运动，20 Hz 已经看不出台阶，
/// 却把重绘成本降到 60 Hz 的三分之一。降低动态效果时直接退化为静止构图。
struct VideoGlassBackdrop: View {
    let theme: AppVisualTheme
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let palette = VideoGlassPalette(theme: theme, isDark: scheme == .dark)
        ZStack {
            palette.base
            if reduceMotion {
                blobs(palette, time: 0)
            } else {
                // 全链路 120Hz 流动极光：解除 20Hz 人为限频，并用 Metal drawingGroup 离屏光栅化三团径向渐变。
                TimelineView(.animation(paused: false)) { context in
                    blobs(palette, time: context.date.timeIntervalSinceReferenceDate)
                }
            }
            // 玻璃需要一个「后面有东西」的错觉：极淡的斜向高光条。
            LinearGradient(colors: [.white.opacity(scheme == .dark ? 0.05 : 0.16),
                                    .clear,
                                    .white.opacity(scheme == .dark ? 0.03 : 0.10)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
                .blendMode(.plusLighter)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func blobs(_ palette: VideoGlassPalette, time: TimeInterval) -> some View {
        GeometryReader { proxy in
            let size = proxy.size
            let span = max(size.width, size.height)
            ZStack {
                blob(palette.primary, diameter: span * 0.95,
                      center: point(size, phase: time / 47, radius: 0.22, tilt: 0.0))
                blob(palette.secondary, diameter: span * 0.80,
                      center: point(size, phase: time / 61 + 1.7, radius: 0.26, tilt: 2.1))
                blob(palette.tertiary, diameter: span * 1.10,
                      center: point(size, phase: time / 79 + 3.4, radius: 0.30, tilt: 4.2))
            }
            .frame(width: size.width, height: size.height)
            .drawingGroup(opaque: false, colorMode: .nonLinear)
        }
    }

    private func blob(_ color: Color, diameter: CGFloat, center: CGPoint) -> some View {
        RadialGradient(colors: [color, color.opacity(0.35), .clear],
                       center: .center, startRadius: 0, endRadius: diameter / 2)
            .frame(width: diameter, height: diameter)
            .position(center)
    }

    /// 缓慢的李萨如轨迹：两个不同频率的正弦叠加，周期互质所以不会「跳回原点」。
    private func point(_ size: CGSize, phase: TimeInterval, radius: Double, tilt: Double) -> CGPoint {
        let a = phase * 2 * .pi + tilt
        let b = phase * 1.37 * .pi + tilt * 0.5
        return CGPoint(x: size.width * (0.5 + radius * sin(a) * 0.5 + radius * 0.35 * cos(b)),
                       y: size.height * (0.5 + radius * cos(a) * 0.5 + radius * 0.30 * sin(b)))
    }
}

/// 两个视频玻璃主题各自的动态色板。深色下饱和度降低、亮度提高，
/// 与项目其余主题「明暗分别调色」的约定一致。
struct VideoGlassPalette {
    let base: LinearGradient
    let primary: Color
    let secondary: Color
    let tertiary: Color

    init(theme: AppVisualTheme, isDark: Bool) {
        switch theme {
        case .videoEmber:
            base = LinearGradient(colors: isDark
                                  ? [Color(red: 0.09, green: 0.04, blue: 0.02), Color(red: 0.20, green: 0.07, blue: 0.04)]
                                  : [Color(red: 1.00, green: 0.97, blue: 0.94), Color(red: 1.00, green: 0.90, blue: 0.84)],
                                  startPoint: .top, endPoint: .bottom)
            primary = Color(red: 1.00, green: 0.55, blue: 0.25).opacity(isDark ? 0.55 : 0.42)
            secondary = Color(red: 0.95, green: 0.24, blue: 0.32).opacity(isDark ? 0.45 : 0.32)
            tertiary = Color(red: 1.00, green: 0.80, blue: 0.36).opacity(isDark ? 0.35 : 0.30)
        default: // videoAurora
            base = LinearGradient(colors: isDark
                                  ? [Color(red: 0.02, green: 0.04, blue: 0.10), Color(red: 0.05, green: 0.09, blue: 0.20)]
                                  : [Color(red: 0.94, green: 0.97, blue: 1.00), Color(red: 0.88, green: 0.93, blue: 1.00)],
                                  startPoint: .top, endPoint: .bottom)
            primary = Color(red: 0.28, green: 0.85, blue: 1.00).opacity(isDark ? 0.50 : 0.40)
            secondary = Color(red: 0.62, green: 0.36, blue: 1.00).opacity(isDark ? 0.55 : 0.36)
            tertiary = Color(red: 0.20, green: 0.95, blue: 0.72).opacity(isDark ? 0.35 : 0.28)
        }
    }
}
