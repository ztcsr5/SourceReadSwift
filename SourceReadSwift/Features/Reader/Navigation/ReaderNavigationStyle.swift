import Foundation

/// The outer UIKit stack owns all prose reader entry points, not SwiftUI's
/// private detail/settings stacks or the system Home gesture.
enum ReaderNavigationStyle: String, CaseIterable, Identifiable {
    case system, parallax, fade, coverFlight, coverInteractive

    static let defaultsKey = "settings.readerNavigationStyle"
    /// Default to the interruptible page-like animator instead of UIKit's
    /// stock push/pop, which reads as a fast card snap on the real entry path.
    static let defaultStyle = ReaderNavigationStyle.parallax
    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "系统平移"
        case .parallax: return "层叠侧滑"
        case .fade: return "淡入淡出"
        case .coverFlight: return "书封开合"
        case .coverInteractive: return "跟手收书"
        }
    }

    var detail: String {
        switch self {
        case .system: return "保持 iOS 原生跟手侧滑"
        case .parallax: return "书页跟手移开，后一页有轻微视差；不放大封面"
        case .fade: return "随手势渐隐，撤回时恢复原页"
        case .coverFlight: return "从封面展开；左缘轻扫后自动收回原位"
        case .coverInteractive: return "从封面展开；左缘拖动收书，可中途撤回"
        }
    }

    var symbol: String {
        switch self {
        case .system: return "rectangle.portrait.and.arrow.right"
        case .parallax: return "rectangle.on.rectangle"
        case .fade: return "circle.lefthalf.filled"
        case .coverFlight: return "arrow.up.left.and.arrow.down.right"
        case .coverInteractive: return "hand.draw"
        }
    }

    var providesAnimator: Bool { self == .parallax || self == .fade }
    var usesSnapshotOverlay: Bool { self == .coverFlight || self == .coverInteractive }
    /// Compatibility transitions need enough time to read as a page movement;
    /// the previous short duration made non-ProMotion devices feel like a card flash.
    var transitionDuration: TimeInterval {
        self == .parallax ? ReaderSlideMotion.layeredDuration : 0.38
    }

    static func resolve(_ raw: String?) -> Self {
        if raw == "paperFold" { return .parallax }
        // The retired cover-zoom preference must never reactivate itself.
        return raw.flatMap(Self.init(rawValue:)) ?? defaultStyle
    }
}
