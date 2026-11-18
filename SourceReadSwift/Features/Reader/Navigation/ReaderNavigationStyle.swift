import Foundation

/// The outer UIKit stack owns all prose reader entry points, not SwiftUI's
/// private detail/settings stacks or the system Home gesture.
enum ReaderNavigationStyle: String, CaseIterable, Identifiable {
    case coverZoom, system, parallax, fade, coverFlight, coverInteractive

    static let defaultsKey = "settings.readerNavigationStyle"
    /// Default to iOS 18+ native zoom transition with resident home; falls back to native system push on older OS.
    static let defaultStyle = ReaderNavigationStyle.coverZoom
    var id: String { rawValue }

    var title: String {
        switch self {
        case .coverZoom: return "原生缩放"
        case .system: return "系统原生"
        case .parallax: return "层叠侧滑"
        case .fade: return "淡入淡出"
        case .coverFlight: return "书封开合"
        case .coverInteractive: return "跟手收书"
        }
    }

    var detail: String {
        switch self {
        case .coverZoom: return "iOS 原生 Zoom 流体展开，主页常驻不重载，支持全屏跟手缩回"
        case .system: return "100% 放行给 iOS 原生推入与 120Hz 跟手边缘侧滑"
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
        case .parallax: return "rectangle.on.rectangle"
        case .fade: return "circle.lefthalf.filled"
        case .coverFlight: return "arrow.up.left.and.arrow.down.right"
        case .coverInteractive: return "hand.draw"
        }
    }

    var usesNativeZoom: Bool { self == .coverZoom }
    var providesAnimator: Bool { self == .parallax || self == .fade }
    var usesSnapshotOverlay: Bool { self == .coverFlight || self == .coverInteractive }
    /// Compatibility transitions need enough time to read as a page movement;
    /// the previous short duration made non-ProMotion devices feel like a card flash.
    var transitionDuration: TimeInterval {
        self == .parallax ? ReaderSlideMotion.layeredDuration : 0.38
    }

    static func resolve(_ raw: String?) -> Self {
        if raw == "paperFold" { return .parallax }
        return raw.flatMap(Self.init(rawValue:)) ?? defaultStyle
    }
}
