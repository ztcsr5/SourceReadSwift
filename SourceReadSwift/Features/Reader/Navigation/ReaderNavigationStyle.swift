import Foundation

/// The outer UIKit stack owns all prose reader entry points, not SwiftUI's
/// private detail/settings stacks or the system Home gesture.
enum ReaderNavigationStyle: String, CaseIterable, Identifiable {
    case coverZoom, system, depthZoom, magneticCard, fanUnfold, bookFlip, sheetRise, parallax, fade, coverFlight, coverInteractive

    static let defaultsKey = "settings.readerNavigationStyle"
    /// Default to iOS 18+ native zoom transition with resident home; falls back to native system push on older OS.
    static let defaultStyle = ReaderNavigationStyle.coverZoom
    /// Curated reader transitions shown in Settings (retains legacy enum cases for decoding compatibility).
    static var pickerCases: [ReaderNavigationStyle] {
        [.coverZoom, .system, .depthZoom, .magneticCard, .fanUnfold, .sheetRise, .parallax, .coverInteractive]
    }
    var id: String { rawValue }

    var title: String {
        switch self {
        case .coverZoom: return "原生缩放"
        case .system: return "系统原生"
        case .depthZoom: return "景深推进"
        case .magneticCard: return "磁吸浮卡"
        case .fanUnfold: return "流光扇开"
        case .bookFlip: return "3D翻书"
        case .sheetRise: return "浮光上浮"
        case .parallax: return "层叠侧滑"
        case .fade: return "淡入淡出"
        case .coverFlight: return "书封开合"
        case .coverInteractive: return "跟手收书"
        }
    }

    var detail: String {
        switch self {
        case .coverZoom: return "iOS 原生 Zoom 流体展开，主页常驻不重载，支持边缘跟手缩回"
        case .system: return "100% 放行给 iOS 原生推入与 120Hz 跟手边缘侧滑"
        case .depthZoom: return "全屏镜头景深推拉，从正在阅读或书籍详情打开均丝滑自然"
        case .magneticCard: return "App Store 风格圆角卡片磁吸展开，底层首页柔和退场，边缘跟手回弹"
        case .fanUnfold: return "书卷轻旋展开入场，搭配柔光景深与 120Hz 边缘跟手回收"
        case .bookFlip: return "绕左侧书脊 3D 翻开精装书页，左缘侧滑可跟手合书"
        case .sheetRise: return "底部圆角弹性上浮，底层首页柔和下沉，左缘跟手收回"
        case .parallax: return "书页跟手移开，底层书架带纵深缩放视差"
        case .fade: return "随手势柔和渐隐，撤回时恢复原页"
        case .coverFlight: return "从封面舒展开合；左缘轻扫后自动收回原位"
        case .coverInteractive: return "从封面展开；左缘跟手拖动收书，可中途撤回"
        }
    }

    var symbol: String {
        switch self {
        case .coverZoom: return "arrow.up.left.and.down.right.magnifyingglass"
        case .system: return "rectangle.portrait.and.arrow.right"
        case .depthZoom: return "viewfinder"
        case .magneticCard: return "rectangle.portrait.inset.filled"
        case .fanUnfold: return "sparkles.rectangle.stack"
        case .bookFlip: return "book.closed"
        case .sheetRise: return "rectangle.bottomhalf.inset.filled"
        case .parallax: return "rectangle.on.rectangle"
        case .fade: return "circle.lefthalf.filled"
        case .coverFlight: return "arrow.up.left.and.arrow.down.right"
        case .coverInteractive: return "hand.draw"
        }
    }

    var usesNativeZoom: Bool { self == .coverZoom }
    var providesAnimator: Bool {
        self == .parallax || self == .fade || self == .depthZoom || self == .magneticCard
            || self == .fanUnfold || self == .bookFlip || self == .sheetRise
    }
    var usesSnapshotOverlay: Bool { self == .coverFlight || self == .coverInteractive }
    /// Compatibility transitions need enough time to read as a page movement;
    /// the previous short duration made non-ProMotion devices feel like a card flash.
    var transitionDuration: TimeInterval {
        switch self {
        case .parallax, .depthZoom, .sheetRise, .magneticCard, .fanUnfold: return ReaderSlideMotion.layeredDuration
        case .bookFlip: return 0.46
        default: return 0.38
        }
    }

    static func resolve(_ raw: String?) -> Self {
        if raw == "paperFold" { return .parallax }
        return raw.flatMap(Self.init(rawValue:)) ?? defaultStyle
    }
}
