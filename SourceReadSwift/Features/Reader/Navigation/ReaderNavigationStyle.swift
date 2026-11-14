import Foundation

/// The outer UIKit stack owns all prose reader entry points, not SwiftUI's
/// private detail/settings stacks or the system Home gesture.
enum ReaderNavigationStyle: String, CaseIterable, Identifiable {
    case system, coverZoom, paperFold, fade

    static let defaultsKey = "settings.readerNavigationStyle"
    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "系统平移"
        case .coverZoom: return "封面归位"
        case .paperFold: return "书页收合"
        case .fade: return "柔和淡入淡出"
        }
    }

    var detail: String {
        switch self {
        case .system: return "保持 iOS 原生跟手侧滑"
        case .coverZoom: return "与可见封面衔接；无封面或旧系统自动用平移"
        case .paperFold: return "向侧边收合，露出后面的原页面"
        case .fade: return "随手势渐隐，撤回时恢复原页"
        }
    }

    var symbol: String {
        switch self {
        case .system: return "rectangle.portrait.and.arrow.right"
        case .coverZoom: return "arrow.down.right.and.arrow.up.left"
        case .paperFold: return "rectangle.on.rectangle"
        case .fade: return "circle.lefthalf.filled"
        }
    }

    var providesAnimator: Bool { self == .paperFold || self == .fade }

    static func resolve(_ raw: String?) -> Self { raw.flatMap(Self.init(rawValue:)) ?? .system }
}
