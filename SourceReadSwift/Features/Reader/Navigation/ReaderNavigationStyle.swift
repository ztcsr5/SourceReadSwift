import Foundation

/// The outer UIKit stack owns all prose reader entry points, not SwiftUI's
/// private detail/settings stacks or the system Home gesture.
enum ReaderNavigationStyle: String, CaseIterable, Identifiable {
    case system, parallax, fade

    static let defaultsKey = "settings.readerNavigationStyle"
    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "系统平移"
        case .parallax: return "层叠侧滑"
        case .fade: return "淡入淡出"
        }
    }

    var detail: String {
        switch self {
        case .system: return "保持 iOS 原生跟手侧滑"
        case .parallax: return "书页跟手移开，后一页有轻微视差；不放大封面"
        case .fade: return "随手势渐隐，撤回时恢复原页"
        }
    }

    var symbol: String {
        switch self {
        case .system: return "rectangle.portrait.and.arrow.right"
        case .parallax: return "rectangle.on.rectangle"
        case .fade: return "circle.lefthalf.filled"
        }
    }

    var providesAnimator: Bool { self == .parallax || self == .fade }

    static func resolve(_ raw: String?) -> Self {
        if raw == "paperFold" { return .parallax }
        // The retired cover-zoom preference must never reactivate itself.
        return raw.flatMap(Self.init(rawValue:)) ?? .system
    }
}
